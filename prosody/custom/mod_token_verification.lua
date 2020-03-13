-- Token authentication
-- Copyright (C) 2015 Atlassian

local jid = require 'util.jid'
local log = module._log
local host = module.host
local st = require 'util.stanza'
local is_admin = require 'core.usermanager'.is_admin
local array = require 'util.array'
local json = require('cjson')

local neturl = require 'net.url'
local parse = neturl.parseQuery
local get_room_from_jid = module:require 'util'.get_room_from_jid
local wrap_async_run = module:require "util".wrap_async_run;

local iterators = require 'util.iterators'

local function get_participants_list(event)
    local participants = array()
    local room = event.room
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
        else
        end
    end
    return json.encode(participants)
end

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

-- Check if array has value
local function has_value(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

-- Disconnect if a token with same email already exists
local function disconnectIfAlreadyJoined(session, stanza)
    local auth_token = session.auth_token

    if auth_token == nil then
        return 0
    end

    local tokenArr = mysplit(auth_token, '.')
    local decryptedData = dec(tokenArr[2])
    local payload = json.decode(decryptedData)
    local email = payload.context.user.email
    log('info', 'Email %s', email)
    local room_address = jid.join(payload.room, 'muc' .. '.' .. payload.sub)
    log('info', 'Room address %s', tostring(room_address))
    local room = get_room_from_jid(room_address)
    log('info', 'Room > %s', tostring(room))
    local participant_count = 0
    local occupants_json = array()

    local emailIds = array()
    if room then
        local occupants = room._occupants
        if occupants then
            for _, occupant in room:each_occupant() do
                -- filter focus as we keep it as hidden participant
                if string.sub(occupant.nick, -string.len('/focus')) ~= '/focus' then
                    for _, pr in occupant:each_session() do
                        local email = pr:get_child_text('email') or ''
                        emailIds:push(email)
                    end
                end
            end
        end
    else
        log('debug', 'no such room exists')
        return 404
    end

    if (has_value(emailIds, email)) then
        -- throw error
        session.send(st.error_reply(stanza, 'cancel', 'not-allowed', 'A user with this email has already joined'))
    end
end

local parentHostName = string.gmatch(tostring(host), '%w+.(%w.+)')()
if parentHostName == nil then
    log('error', 'Failed to start - unable to get parent hostname')
    return
end

local parentCtx = module:context(parentHostName)
if parentCtx == nil then
    log('error', 'Failed to start - unable to get parent context for host: %s', tostring(parentHostName))
    return
end

local token_util = module:require 'token/util'.new(parentCtx)

-- no token configuration
if token_util == nil then
    return
end

log(
    'debug',
    '%s - starting MUC token verifier app_id: %s app_secret: %s allow empty: %s',
    tostring(host),
    tostring(token_util.appId),
    tostring(token_util.appSecret),
    tostring(token_util.allowEmptyToken)
)

local function verify_user(session, stanza, event)
    log('debug', 'Session token: %s, session room: %s', tostring(session.auth_token), tostring(session.jitsi_meet_room))

    -- token not required for admin users
    local user_jid = stanza.attr.from
    if is_admin(user_jid) then
        log('debug', 'Token not required from admin user: %s', user_jid)
        return nil
    end

    log('debug', 'Will verify token for user: %s, room: %s ', user_jid, stanza.attr.to)
    if not token_util:verify_room(session, stanza.attr.to) then
        log('error', 'Token %s not allowed to join: %s', tostring(session.auth_token), tostring(stanza.attr.to))
        session.send(st.error_reply(stanza, 'cancel', 'not-allowed', 'Room and token mismatched'))
        return false -- we need to just return non nil
    end
    log('debug', 'allowed: %s to enter/create room: %s', user_jid, stanza.attr.to)

    local participants = disconnectIfAlreadyJoined(session, stanza)
    get_participants_list(event)
end

module:hook(
    'muc-room-pre-create',
    function(event)
        local origin, stanza = event.origin, event.stanza
        log('debug', 'pre create: %s %s', tostring(origin), tostring(stanza))
        return verify_user(origin, stanza, event)
    end
)

module:hook(
    'muc-occupant-pre-join',
    function(event)
        local origin, room, stanza = event.origin, event.room, event.stanza
        log('debug', 'pre join: %s %s', tostring(room), tostring(stanza))
        return verify_user(origin, stanza, event)
    end
)

local function is_moderator_present(room)
    local roles = array()
    if room then
        local occupants = room._occupants
        if occupants then
            for _, occupant in room:each_occupant() do
                -- filter focus as we keep it as hidden participant
                if string.sub(occupant.nick, -string.len('/focus')) ~= '/focus' then
                    log('info', 'role > %s', occupant.role)
                    roles:push(occupant.role)
                end
            end
        end
    else
        log('debug', 'no such room exists')
        return 404
    end

    if (has_value(roles, 'moderator')) then
        return true
    else
        return false
    end
end

-- module:hook(
--     'muc-occupant-left',
--     function(event)
--         -- if shouldWeCloseRoom(event.origin.auth_token) then
--         --     --FIRE OTHER PARTICIPANTS FIRST
--         --     event.room:clear()
--         --     --Destroy Room
--         --     event.room:destroy()
--         -- end
--         local room = event.room
--         local has_moderator = is_moderator_present(room)

--         if (has_moderator) then
--           log('info','A moderator exists')
--         else
--           log('info','No moderator exists. Removing everyone')
--           event.room:clear();
--           event.room:destroy();
--         end
--         log('info', "%s",tostring(has_moderator))
--     end,
--     150
-- )

function module.load()
    module:depends('http');
    module:provides(
        'http',
        {
            default_path = '/',
            route = {
                ['GET participants-list'] = function(event)
                    return wrap_async_run(event, get_participants_list)
                end;
            }
        }
    )
end
