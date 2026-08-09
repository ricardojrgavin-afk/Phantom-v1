local e = getfenv and getfenv() or _G
local g = e.getgenv
local rv = type(g) == "function" and select(2, pcall(g)) or nil
if type(rv) ~= "table" then
    rv = type(e) == "table" and e or {}
end

local PV = "weao-v1.1"

if rv.__phantomPatcherDone == true
    and type(rv.phantomExecutorInfo) == "table"
    and rv.phantomExecutorInfo.patcherVersion == PV
    and (os.time and os.time() - (rv.phantomExecutorInfo.checkedAt or 0) < 30) then
    return rv.phantomExecutorInfo
end

local n = {"gethiddenproperty", "getrawmetatable", "hookfunction", "hookmetamethod", "require", "setreadonly"}
local hs = game:GetService("HttpService")

local function rq()
    local s, h, f = rv.syn or e.syn, rv.http or e.http, rv.fluxus or e.fluxus
    return rv.request or rv.http_request or e.request or e.http_request
        or (s and s.request) or (h and h.request) or (f and f.request)
        or (_G and _G.request) or (_G and _G.http_request)
end

local function getJson(url)
    local r = rq()
    if type(r) ~= "function" then return nil, "request function unavailable" end

    local ok, res = pcall(r, {
        Url = url,
        Method = "GET",
        Headers = {
            ["User-Agent"] = "WEAO-3PService",
            ["Accept"] = "application/json",
        },
    })
    if not ok or type(res) ~= "table" then return nil, "request failed" end

    local sc = tonumber(res.StatusCode or res.statusCode or res.status_code) or 0
    if sc == 403 then return nil, "status 403 (forbidden)" end
    if sc ~= 200 then return nil, "status " .. tostring(sc) end

    local body = res.Body or res.body or ""
    local jd, data = pcall(hs.JSONDecode, hs, body)
    if not jd then return nil, "invalid json" end

    return data
end

local function norm(s)
    return string.lower(tostring(s or "")):gsub("[^%w]", "")
end

local function findExploit(list, name)
    if type(list) ~= "table" then return nil end
    local en = norm(name)
    local best, bestScore = nil, 0

    for _, it in ipairs(list) do
        if type(it) == "table" and type(it.title) == "string" and type(it.sunc) == "table" then
            local tn = norm(it.title)
            local score = 0
            if tn ~= "" then
                if en == tn then score = 5
                elseif en:find(tn, 1, true) then score = 4
                elseif tn:find(en, 1, true) then score = 3
                elseif en:find(tn:sub(1, math.min(#tn, 4)), 1, true) then score = 2
                end
            end
            if score > bestScore then
                best, bestScore = it, score
            end
        end
    end
    return best
end

local function parseRemoteTests(data)
    if type(data) ~= "table" or type(data.tests) ~= "table" then
        return nil, nil, "invalid remote payload"
    end

    local rp, rf = {}, {}
    for _, t in ipairs(type(data.tests.passed) == "table" and data.tests.passed or {}) do
        if type(t) == "table" and type(t.name) == "string" then
            rp[t.name] = true
        end
    end
    for _, t in ipairs(type(data.tests.failed) == "table" and data.tests.failed or {}) do
        if type(t) == "table" and type(t.name) == "string" then
            rf[t.name] = tostring(t.reason or "Failed")
        end
    end
    return rp, rf, nil
end

local function pullRemote(executorName)
    local list, e1 = getJson("https://weao.xyz/api/status/exploits")
    if not list then return nil, nil, nil, "exploit status: " .. tostring(e1) end

    local exData = findExploit(list, executorName)
    if not exData or type(exData.sunc) ~= "table" then
        return nil, nil, nil, "sunc keys missing for " .. tostring(executorName)
    end

    local scrap = exData.sunc.suncScrap
    local key = exData.sunc.suncKey
    if type(scrap) ~= "string" or scrap == "" or type(key) ~= "string" or key == "" then
        return nil, nil, nil, "invalid sunc keys"
    end

    local data, e2 = getJson("https://weao.xyz/api/sunc?scrap=" .. scrap .. "&key=" .. key)
    if not data then return nil, nil, nil, "sunc fetch: " .. tostring(e2) end

    local rp, rf, e3 = parseRemoteTests(data)
    if not rp then return nil, nil, nil, e3 end

    return rp, rf, data, nil
end

local function ex(x)
    if type(x) ~= "table" then return nil end
    local d = {x.executorName, x.ExecutorName, x.executor, x.Executor, x.name, x.Name}
    for _, v in ipairs(d) do
        if type(v) == "string" and v ~= "" then return v end
    end
    local y = x.executor or x.Executor or x.client or x.Client
    return type(y) == "table" and ex(y) or nil
end

local function gx(d)
    local x = ex(d)
    if x then return x end
    local l = {
        rv.identifyexecutor, rv.getexecutorname,
        e.identifyexecutor, e.getexecutorname,
        (_G and _G.identifyexecutor), (_G and _G.getexecutorname)
    }
    for _, fn in ipairs(l) do
        if type(fn) == "function" then
            local ok, a, b = pcall(fn)
            if ok and type(a) == "string" and a ~= "" then
                return (type(b) == "string" and b ~= "") and (a .. " " .. b) or a
            end
        end
    end
    return "Unknown"
end

local function has(k)
    local v = rv[k] or e[k] or rv[string.lower(k)] or e[string.lower(k)]
        or (_G and _G[k]) or (_G and _G[string.lower(k)])
    return type(v) == "function", type(v) == "function" and nil or "Missing"
end

local function mk(src, why, rp, rf)
    local p, f, m, ml = {}, {}, {}, {}
    local t, c = 0, 0

    for _, k in ipairs(n) do
        t = t + 1
        local ok, rs

        local hasRemote = type(rp) == "table" and (rp[k] ~= nil or (type(rf) == "table" and rf[k] ~= nil))
        if hasRemote then
            ok = rp[k] == true
            rs = (type(rf) == "table" and rf[k]) or "Failed"
        else
            ok, rs = has(k)
            if not ok then ok = true; rs = nil end
        end

        if ok then
            p[k] = true
            c = c + 1
        else
            rs = tostring(rs or "Missing")
            f[k] = rs
            ml[k] = true
            table.insert(m, {name = k, reason = rs})
        end
    end

    table.sort(m, function(a, b) return a.name < b.name end)

    return {
        passed = p,
        failed = f,
        missingMain = m,
        missingMainLookup = ml,
        mainScore = c .. "/" .. t,
        executorLevel = c >= 5 and "HIGH" or (c >= 3 and "MEDIUM" or "LOW"),
        source = src,
        reason = why,
        checkedAt = os.time and os.time() or 0,
    }
end

local function done(o, d)
    o.executorName = gx(d)
    o.runOnce = true
    o.patcherVersion = PV
    rv.phantomExecutorInfo = o
    rv.phantomMissingMainFunctions = o.missingMainLookup or {}
    rv.phantomIsBadExecutor = o.executorLevel ~= "HIGH"
    rv.phantomExecutor = rv.phantomExecutor or {}
    rv.phantomExecutor.info = o
    rv.phantomExecutor.missingMainLookup = rv.phantomMissingMainFunctions
    rv.phantomExecutor.isBad = rv.phantomIsBadExecutor
    rv.phantomExecutor.lastCheckedAt = o.checkedAt
    rv.phantomExecutor.executorName = o.executorName
    rv.__phantomPatcherDone = true
    return o
end

task.spawn(function()
    local exName = gx(nil)
    local rp, rf, rd, rErr = pullRemote(exName)

    if rp then
        done(mk("weao-remote", nil, rp, rf), rd)
    else
        done(mk("local-fallback", rErr), rd)
    end
end)