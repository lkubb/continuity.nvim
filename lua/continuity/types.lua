---@class ContinuityState
---@field registry table<string,ContinuityCwdData>

---@class ContinuitySession
---@field uuid string
---@field cwd string
---@field branch string?

---@class ContinuityCwdData
---@field sessions table<string,ContinuitySession[]>
