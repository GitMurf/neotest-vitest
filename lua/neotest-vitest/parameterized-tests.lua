local lib = require("neotest.lib")
local vitest_util = require("neotest-vitest.vitest-util")

local M = {}

-- Traverses through whole Tree and returns all parameterized tests positions.
-- All parameterized test positions should have `is_parameterized` property on it.
-- @param positions neotest.Tree
-- @return neotest.Tree[]
function M.get_parameterized_tests_positions(positions)
  local parameterized_tests_positions = {}

  for _, value in positions:iter_nodes() do
    local data = value:data()

    if data.type == "test" and data.is_parameterized == true then
      parameterized_tests_positions[#parameterized_tests_positions + 1] = value
    end
  end

  return parameterized_tests_positions
end

-- Synchronously runs `vitest` in `file_path` directory skipping all tests and returns `vitest` output.
-- Output have all of the test names inside it. It skips all tests by adding
-- extra `--testPathPattern` parameter to vitest command with placeholder string that should never exist.
-- @param file_path string - path to file to search for tests
-- @return table - parsed vitest test results
-- local function run_vitest_test_discovery(file_path)
function M.run_vitest_test_discovery(file_path)
  local binary = vitest_util.getVitestCommand(file_path)
  local command = vim.split(binary, "%s+")

  vim.list_extend(command, {
    "list",
    -- "--no-coverage",
    -- TODO: see if comparable vitest options to these jest ones
    -- Does not look like there is a way to get the location in `vitest list`
    -- "--testLocationInResults",
    -- "--verbose",
    "--json",
    "--dir",
    file_path,
    -- "-t",
    -- "@______________PLACEHOLDER______________@",
  })

  -- vim.notify("run_vitest_test_discovery > updated command: " .. vim.inspect(command))

  -- local test_command = {
  --   "C:\\01_Local_Only\\nolocron-dev\\gitmurf-private\\nolocron-beta-private\\node_modules\\.bin\\vitest.CMD",
  --   "list",
  -- }
  -- -- local vim_fn_sys_result = vim.fn.system(test_command)
  -- -- vim.notify("run_vitest_test_discovery > vim_fn_sys_result: " .. vim.inspect(vim_fn_sys_result))

  local result = { lib.process.run(command, { stdout = true }) }
  -- local result = { lib.process.run(test_command, { stdout = true }) }
  -- vim.notify("run_vitest_test_discovery > result: " .. vim.inspect(result))

  if not result[2] then
    return nil
  end

  local vitest_json_string = result[2].stdout

  if not vitest_json_string or #vitest_json_string == 0 then
    return nil
  end

  -- vim.notify("run_vitest_test_discovery: " .. vim.inspect(vitest_json_string))

  return vim.json.decode(vitest_json_string, { luanil = { object = true } })
end

-- Searches through whole `vitest` command output and returns array of all tests at given `position`.
-- @param vitest_output table
-- @param position number[]
-- @return { keyid: string, name: string }[]
local function get_tests_ids_at_position(vitest_output, position)
  local test_ids_at_position = {}
  for _, testResult in pairs(vitest_output.testResults) do
    local testFile = testResult.name

    for _, assertionResult in pairs(testResult.assertionResults) do
      local location, name = assertionResult.location, assertionResult.title

      if position[1] <= location.line - 1 and position[3] >= location.line - 1 then
        local keyid = vitest_util.get_test_full_id_from_test_result(testFile, assertionResult)

        test_ids_at_position[#test_ids_at_position + 1] = { keyid = keyid, name = name }
      end
    end
  end

  return test_ids_at_position
end

-- First runs `vitest` in `file_path` to get all of the tests in the file. Then it takes all of
-- the parameterized tests and finds tests that were in the same position as parameterized test
-- and adds new tests (with range=nil) to the parameterized test.
-- @param file_path string
-- @param each_tests_positions neotest.Tree[]
function M.enrich_positions_with_parameterized_tests(
  file_path,
  parsed_parameterized_tests_positions
)
  local vitest_test_discovery_output = run_vitest_test_discovery(file_path)

  if vitest_test_discovery_output == nil then
    return
  end

  for _, value in pairs(parsed_parameterized_tests_positions) do
    local data = value:data()

    local parameterized_test_results_for_position =
      get_tests_ids_at_position(vitest_test_discovery_output, data.range)

    for _, test_result in ipairs(parameterized_test_results_for_position) do
      local new_data = {
        id = test_result.keyid,
        name = test_result.name,
        path = data.path,
      }
      new_data.range = nil

      local new_pos = value:new(new_data, {}, value._key, {}, {})
      value:add_child(new_data.id, new_pos)
    end
  end
end

local VITEST_PARAMETER_TYPES = {
  "%%p",
  "%%s",
  "%%d",
  "%%i",
  "%%f",
  "%%j",
  "%%o",
  "%%#",
  "%%%%",
}

-- Replaces all of the vitest parameters (named and unnamed) with `.*` regex pattern.
-- It allows to run all of the parameterized tests in a single run. Idea inpired by Webstorm vitest plugin.
-- @param test_name string - test name with escaped characters
-- @returns string
function M.replaceTestParametersWithRegex(test_name)
  -- replace named parameters: named characters can be single word (like $parameterName)
  -- or field access words (like $parameterName.fieldName)
  local result = test_name:gsub("\\$[%a%.]+", ".*")

  for _, parameter in ipairs(VITEST_PARAMETER_TYPES) do
    result = result:gsub(parameter, ".*")
  end

  return result
end

return M
