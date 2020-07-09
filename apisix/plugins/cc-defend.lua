---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by dingweiqiang.
--- DateTime: 2020-07-08 15:02
---
local core = require("apisix.core")
local ipmatcher = require("resty.ipmatcher")
local plugin_name = "cc-defend"

local schema = {
    type = "object",
    properties = {
        switch = {
            type = "string",
            enum = {"on", "off"},
            default = "on",
        },
        count = {type = "integer", minimum = 0},
        time_window = {type = "integer",  minimum = 0},
        black_time = {type = "integer",  default = 10},
        key = {
            type = "string",
            enum = {"remote_addr", "server_addr", "http_x_real_ip",
                    "http_x_forwarded_for"},
        },
        rejected_code = {type = "integer", minimum = 200, maximum = 600,
                         default = 503},
        whitelist = {
            type = "array",
            items = {type = "string", anyOf = core.schema.ip_def},
        },
    },
    additionalProperties = false,
    required = {"count", "time_window", "key"},
}

local _M = {
    version = 0.1,
    priority = 3001,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    return true
end

local function create_ip_matcher(ip_list)
    local ip, err = ipmatcher.new(ip_list)
    if not ip then
        core.log.error("failed to create ip matcher: ", err,
                " ip list: ", core.json.delay_encode(ip_list))
        return nil
    end

    return ip
end

function _M.access(conf, ctx)
    if conf.switch ~= "on" then
        return
    end

    local ip = ctx.var[conf.key] or ""
    local ip_matcher = create_ip_matcher(conf.whitelist or {})
    if ip_matcher then
        local ok = ip_matcher:match(ip)
        if ok == true then
            return
        end
    end
    local key = ip .. ctx.conf_type .. ctx.conf_version
    core.log.info("limit key: ", key)

    local ngx_shared_dict_name = "plugin-"..plugin_name
    local limit = ngx.shared[ngx_shared_dict_name]

    local black_flag = limit:get(key .. "black")
    if (black_flag ~= nil) then
        local log_flag = limit:get(key .. "log")
        if (log_flag == nil) then
            limit:set(key .. "log", "1", 60)
            local _log = {}
            _log.attackField = "ip"
            _log.attackRule = "cc"
            _log.attackContent = ip
            _log.attackAction = "deny"
            _log.rulesId = "30100000"
            ctx.waf_log = ctx.waf_log or {}
            table.insert(ctx.waf_log, _log)
        else
            ctx.isCC = true
        end
        core.log.error("The number of visits exceeded the limit per unit time")
        return conf.rejected_code
    else
        local req= limit:get(key)
        if req then
            if req > conf.count then
                local log_flag = limit:get(key .. "log")
                if (log_flag == nil) then
                    limit:set(key .. "log", "1", 60)
                    local _log = {}
                    _log.attackField = "ip"
                    _log.attackRule = "cc"
                    _log.attackContent = ip
                    _log.attackAction = "deny"
                    _log.rulesId = "30100000"
                    ctx.waf_log = ctx.waf_log or {}
                    table.insert(ctx.waf_log, _log)
                else
                    ctx.isCC = true
                end
                limit:set(key .. "black", "1", conf.black_time)
                core.log.error("The number of visits exceeded the limit per unit time")
                return conf.rejected_code
            end
        end
    end
end

function _M.log(conf, ctx)
    if conf.switch ~= "on" then
        return
    end

    local ip = ctx.var[conf.key] or ""
    local ip_matcher = create_ip_matcher(conf.whitelist or {})
    if ip_matcher then
        local ok = ip_matcher:match(ip)
        if ok == true then
            return
        end
    end

    local key = ip .. ctx.conf_type .. ctx.conf_version
    core.log.error("limit key: ", key)

    local ngx_shared_dict_name = "plugin-"..plugin_name
    local limit = ngx.shared[ngx_shared_dict_name]
    local req = limit:get(key)

    local black_flag = limit:get(key .. "black")
    if (black_flag == nil) then
        if req then
            limit:incr(key, 1)
        else
            limit:set(key, 1, conf.time_window)
        end
    end
end

return _M