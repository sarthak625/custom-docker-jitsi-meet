-- Prosody IM
-- Copyright (C) 2017 Atlassian
--

local jid = require 'util.jid'
local it = require 'util.iterators'
local json = require 'util.json'
local iterators = require 'util.iterators'
local array = require 'util.array'
local wrap_async_run = module:require 'util'.wrap_async_run

local tostring = tostring
local neturl = require 'net.url'
local parse = neturl.parseQuery

-- Lua jwt for jwt auth
local jwt = require "luajwt"

-- option to enable/disable room API token verifications
local enableTokenVerification = module:get_option_boolean('enable_roomsize_token_verification', true)

local token_util = module:require 'token/util'.new(module)
local get_room_from_jid = module:require 'util'.get_room_from_jid

-- no token configuration but required
if token_util == nil and enableTokenVerification then
    log('error', 'no token configuration but it is required')
    return
end

local json = require('cjson')
-- Function to split string
local function mysplit(inputstr, sep)
    if sep == nil then
        sep = '%s'
    end
    local t = {}
    for str in string.gmatch(inputstr, '([^' .. sep .. ']+)') do
        table.insert(t, str)
    end
    return t
end

-- Function for base 64 decoding
-- Dependent on cjson luarocks module
local function dec(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^' .. b .. '=]', '')
    return (data:gsub(
        '.',
        function(x)
            if (x == '=') then
                return ''
            end
            local r, f = '', (b:find(x) - 1)
            for i = 6, 1, -1 do
                r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and '1' or '0')
            end
            return r
        end
    ):gsub(
        '%d%d%d?%d?%d?%d?%d?%d?',
        function(x)
            if (#x ~= 8) then
                return ''
            end
            local c = 0
            for i = 1, 8 do
                c = c + (x:sub(i, i) == '1' and 2 ^ (8 - i) or 0)
            end
            return string.char(c)
        end
    ))
end

-- required parameter for custom muc component prefix,
-- defaults to "conference"
local muc_domain_prefix = module:get_option_string('muc_mapper_domain_prefix', 'conference')

--- Verifies room name, domain name with the values in the token
-- @param token the token we received
-- @param room_address the full room address jid
-- @return true if values are ok or false otherwise
function verify_token(token, room_address)
    if not enableTokenVerification then
        return true
    end

    -- if enableTokenVerification is enabled and we do not have token
    -- stop here, cause the main virtual host can have guest access enabled
    -- (allowEmptyToken = true) and we will allow access to rooms info without
    -- a token
    if token == nil then
        log('warn', 'no token provided')
        return false
    end

    local session = {}
    session.auth_token = token
    local verified, reason = token_util:process_and_verify_token(session)
    if not verified then
        log('warn', 'not a valid token %s', tostring(reason))
        return false
    end

    if not token_util:verify_room(session, room_address) then
        log('warn', 'Token %s not allowed to join: %s', tostring(token), tostring(room_address))
        return false
    end

    return true
end

--- Handles request for retrieving the room size
-- @param event the http event, holds the request query
-- @return GET response, containing a json with participants count,
--         tha value is without counting the focus.
function handle_get_room_size(event)
    log('info', 'Called handle_get_room_size')

    if (not event.request.url.query) then
        return 400
    end

    local params = parse(event.request.url.query)
    local room_name = params['room']
    local domain_name = params['domain']
    local subdomain = params['subdomain']

    local room_address = jid.join(room_name, muc_domain_prefix .. '.' .. domain_name)

    if subdomain and subdomain ~= '' then
        room_address = '[' .. subdomain .. ']' .. room_address
    end

    if not verify_token(params['token'], room_address) then
        return 403
    end

    local room = get_room_from_jid(room_address)
    local participant_count = 0

    log('debug', 'Querying room %s', tostring(room_address))

    if room then
        local occupants = room._occupants
        if occupants then
            participant_count = iterators.count(room:each_occupant())
        end
        log('debug', 'there are %s occupants in room', tostring(participant_count))
    else
        log('debug', 'no such room exists')
        return 404
    end

    if participant_count > 1 then
        participant_count = participant_count - 1
    end

    return [[{"participants":]] .. participant_count .. [[}]]
end

--- Handles request for retrieving the room participants details
-- @param event the http event, holds the request query
-- @return GET response, containing a json with participants details
function handle_get_room(event)
    if (not event.request.url.query) then
        return 400
    end

    local params = parse(event.request.url.query)
    local room_name = params['room']
    local domain_name = params['domain']
    local subdomain = params['subdomain']
    local room_address = jid.join(room_name, muc_domain_prefix .. '.' .. domain_name)

    if subdomain ~= '' then
        room_address = '[' .. subdomain .. ']' .. room_address
    end

    if not verify_token(params['token'], room_address) then
        return 403
    end

    local room = get_room_from_jid(room_address)
    local participant_count = 0
    local occupants_json = array()

    log('debug', 'Querying room %s', tostring(room_address))

    if room then
        local occupants = room._occupants
        if occupants then
            participant_count = iterators.count(room:each_occupant())
            for _, occupant in room:each_occupant() do
                -- filter focus as we keep it as hidden participant
                if string.sub(occupant.nick, -string.len('/focus')) ~= '/focus' then
                    for _, pr in occupant:each_session() do
                        local nick = pr:get_child_text('nick', 'http://jabber.org/protocol/nick') or ''
                        local email = pr:get_child_text('email') or ''
                        occupants_json:push(
                            {
                                jid = tostring(occupant.nick),
                                email = tostring(email),
                                display_name = tostring(nick)
                            }
                        )
                    end
                end
            end
        end
        log('debug', 'there are %s occupants in room', tostring(participant_count))
    else
        log('debug', 'no such room exists')
        return 404
    end

    if participant_count > 1 then
        participant_count = participant_count - 1
    end

    return json.encode(occupants_json)
end

local function get_participants_list(event)
    if (not event.request.url.query) then
        return 400
    end
    log('info', 'Called get participants list')

    local params = parse(event.request.url.query)
    local room_name = params['room']
    local domain_name = params['domain']
    local token = params['token']
    local room_address = jid.join(room_name, 'muc' .. '.' .. domain_name)
    local room = get_room_from_jid(room_address)

    log('info', 'Tried to get room jid for address %s', room_address)

    if not token then
        return 404
    end

    if not verify_token(token, room_address) then
        return 403
    else
        local token_arr = mysplit(token, '.')
        local decrypted_data = dec(token_arr[2])
        local payload = json.decode(decrypted_data)
        local exit_token_name = payload.name

        if not (exit_token_name == 'backend_token') then
            return 403
        end
    end

    local participants = array()
    if room then
        local occupants = room._occupants
        if occupants then
            for _, occupant in room:each_occupant() do
                -- filter focus as we keep it as hidden participant
                participant = {}
                if string.sub(occupant.nick, -string.len('/focus')) ~= '/focus' then
                    participant['role'] = occupant.role
                    for _, pr in occupant:each_session() do
                        local email = pr:get_child_text('email') or ''
                        participant['email'] = email
                        participants:push(participant)
                    end
                end
            end
        end
    end
    return json.encode(participants)
end

local function shutdown_room(event)
    if (not event.request.url.query) then
        return 400
    end
    log('info', 'Called get participants list')

    local params = parse(event.request.url.query)

    local key = os.getenv('ROOM_CREATION_SECRET')
    local secret = params['secret']

    if key ~= secret then
      return 403
    end

    local room_name = params['room']
    local domain_name = params['domain']

    if not room_name then
        return 404
    end

    if not domain_name then
        return 404
    end

    local room_address = jid.join(room_name, 'muc' .. '.' .. domain_name)
    local room = get_room_from_jid(room_address)

    if room then
        room:clear()
        room:destroy()
    else
        return 404
    end
end

-- A random uuid generator
local random = math.random
local function uuid()
    local template = 'xxxxxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and random(0, 0xf) or random(8, 0xb)
        return string.format('%x', v)
    end)
end

local key = os.getenv('JWT_APP_SECRET')
local alg = 'HS256'

local function generateJWT(room_name)
  local payload = {
    aud = '*',
    iss = os.getenv('JWT_APP_ID'),
    sub = 'meet.jitsi',
    room = room_name,
    moderator = false,
    nbf = os.time(),
    exp = os.time() + 3600
  }

  local token, err = jwt.encode(payload, key, alg)

  if not err then
    return token
  end
  return err
end

local function create_room(event)
    if (not event.request.url.query) then
        return 400
    end
    log('info', 'Called create room')

    
    local params = parse(event.request.url.query)
    local domain_name = params['domain']
    
    local key = os.getenv('ROOM_CREATION_SECRET')
    local secret = params['secret']

    if key ~= secret then
      return 403
    end

    if not domain_name then
        return 404
    end

    -- Logic to create new room
    room_name = uuid()
    log('info', room_name)
    token = generateJWT(room_name)
    log('info', token)
    
    return room_name .. '?jwt=' .. token
end

function module.load()
    module:depends('http')
    module:provides(
        'http',
        {
            default_path = '/',
            route = {
                ['GET room-size'] = function(event)
                    return wrap_async_run(event, handle_get_room_size)
                end,
                ['GET sessions'] = function()
                    return tostring(it.count(it.keys(prosody.full_sessions)))
                end,
                ['GET room'] = function(event)
                    return wrap_async_run(event, handle_get_room)
                end,
                ['GET participants-list'] = function(event)
                    return wrap_async_run(event, get_participants_list)
                end,
                ['GET shutdown-room'] = function(event)
                    return wrap_async_run(event, shutdown_room)
                end,
                ['GET create-room'] = function(event)
                    return wrap_async_run(event, create_room)
                end
            }
        }
    )
end
