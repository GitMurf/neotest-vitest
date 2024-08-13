local util = require("neotest-vitest.util")

local M = {}

function M.is_callable(obj)
  return type(obj) == "function" or (type(obj) == "table" and obj.__call)
end

-- Returns vitest binary from `node_modules` if that binary exists and `vitest` otherwise.
---@param path string
---@return string
function M.getVitestCommand(path)
  local gitAncestor = util.find_git_ancestor(path)

  local function findBinary(p)
    local rootPath = util.find_node_modules_ancestor(p)
    local vitestBinary = util.path.join(rootPath, "node_modules", ".bin", "vitest")

    if util.path.exists(vitestBinary) then
      return vitestBinary
    end

    -- If no binary found and the current directory isn't the parent
    -- git ancestor, let's traverse up the tree again
    if rootPath ~= gitAncestor then
      return findBinary(util.path.dirname(rootPath))
    end
  end

  local foundBinary = findBinary(path)

  if foundBinary then
    return foundBinary
  end

  return "vitest"
end

local vitestConfigPattern = util.root_pattern("vitest.config.{js,ts}")

-- Returns vitest config file path if it exists.
---@param path string
---@return string|nil
function M.getVitestConfig(path)
  local rootPath = vitestConfigPattern(path)

  if not rootPath then
    return nil
  end

  local vitestJs = util.path.join(rootPath, "vitest.config.js")
  local vitestTs = util.path.join(rootPath, "vitest.config.ts")

  if util.path.exists(vitestTs) then
    return vitestTs
  end

  return vitestJs
end

-- Returns neotest test id from vitest test result.
-- @param testFile string
-- @param assertionResult table
-- @return string
function M.get_test_full_id_from_test_result(testFile, assertionResult)
  local keyid = testFile
  local name = assertionResult.title

  for _, value in ipairs(assertionResult.ancestorTitles) do
    keyid = keyid .. "::" .. value
  end

  keyid = keyid .. "::" .. name

  return keyid
end

return M
