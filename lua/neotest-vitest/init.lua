---@diagnostic disable: undefined-field
local async = require("neotest.async")
local lib = require("neotest.lib")
local logger = require("neotest.logging")
local util = require("neotest-vitest.util")
-- local parameterized_tests = require("neotest-vitest.parameterized-tests")

---@class neotest.VitestOptions
---@field vitestCommand? string|fun(): string
---@field vitestConfigFile? string|fun(): string
---@field env? table<string, string>|fun(): table<string, string>
---@field cwd? string|fun(): string
---@field filter_dir? fun(name: string, relpath: string, root: string): boolean
---@field is_test_file? fun(file_path: string): boolean

---@class neotest.Adapter
local adapter = { name = "neotest-vitest" }

local rootPackageJson = vim.fn.getcwd() .. "/package.json"

---@param packageJsonContent string
---@return boolean
local function hasVitestDependencyInJson(packageJsonContent)
  local parsedPackageJson = vim.json.decode(packageJsonContent)

  for _, dependencyType in ipairs({ "dependencies", "devDependencies" }) do
    if parsedPackageJson[dependencyType] then
      for key, _ in pairs(parsedPackageJson[dependencyType]) do
        if key == "vitest" then
          return true
        end
      end
    end
  end

  return false
end

---@return boolean
local function hasRootProjectVitestDependency()
  local success, packageJsonContent = pcall(lib.files.read, rootPackageJson)
  if not success then
    print("cannot read package.json")
    return false
  end

  return hasVitestDependencyInJson(packageJsonContent)
end

---@param path string
---@return boolean
local function hasVitestDependency(path)
  local rootPath = lib.files.match_root_pattern("package.json")(path)

  if not rootPath then
    return false
  end

  local success, packageJsonContent = pcall(lib.files.read, rootPath .. "/package.json")
  if not success then
    print("cannot read package.json")
    return false
  end

  return hasVitestDependencyInJson(packageJsonContent) or hasRootProjectVitestDependency()
end

adapter.root = function(path)
  return lib.files.match_root_pattern("package.json")(path)
end

function adapter.filter_dir(name, _relpath, _root)
  return name ~= "node_modules"
end

---@param file_path? string
---@return boolean
function adapter.is_test_file(file_path)
  if file_path == nil then
    return false
  end
  local is_test_file = false

  if string.match(file_path, "__tests__") then
    is_test_file = true
  end

  for _, x in ipairs({ "spec", "test" }) do
    for _, ext in ipairs({ "js", "jsx", "coffee", "ts", "tsx" }) do
      if string.match(file_path, "%." .. x .. "%." .. ext .. "$") then
        is_test_file = true
        goto matched_pattern
      end
    end
  end
  ::matched_pattern::
  return is_test_file and hasVitestDependency(file_path)
end

---@async
---@return neotest.Tree | nil
function adapter.discover_positions(path)
  local query = [[
    ; -- Namespaces --
    ; Matches: `describe('context')`
    ((call_expression
      function: (identifier) @func_name (#eq? @func_name "describe")
      arguments: (arguments (string (string_fragment) @namespace.name) (arrow_function))
    )) @namespace.definition
    ; Matches: `describe.only('context')`
    ((call_expression
      function: (member_expression
        object: (identifier) @func_name (#any-of? @func_name "describe")
      )
      arguments: (arguments (string (string_fragment) @namespace.name) (arrow_function))
    )) @namespace.definition
    ; Matches: `describe.each(['data'])('context')`
    ((call_expression
      function: (call_expression
        function: (member_expression
          object: (identifier) @func_name (#any-of? @func_name "describe")
        )
      )
      arguments: (arguments (string (string_fragment) @namespace.name) (arrow_function))
    )) @namespace.definition

    ; -- Tests --
    ; Matches: `test('test') / it('test')`
    ((call_expression
      function: (identifier) @func_name (#any-of? @func_name "it" "test")
      arguments: (arguments (string (string_fragment) @test.name) (arrow_function))
    )) @test.definition
    ; Matches: `test.only('test') / it.only('test')`
    ((call_expression
      function: (member_expression
        object: (identifier) @func_name (#any-of? @func_name "test" "it")
      )
      arguments: (arguments (string (string_fragment) @test.name) (arrow_function))
    )) @test.definition
    ; Matches: `test.each(['data'])('test') / it.each(['data'])('test')`
    ((call_expression
      function: (call_expression
        function: (member_expression
          object: (identifier) @func_name (#any-of? @func_name "it" "test")
          property: (property_identifier) @each_property (#eq? @each_property "each")
        )
      )
      arguments: (arguments (string (string_fragment) @test.name) (arrow_function))
    )) @test.definition
  ]]

  -- FLAG: this is from neotest-jest and not sure if I need it right now
  -- -- Enrich `it.each` tests with metadata about TS node position
  -- function adapter.build_position(file_path, source, captured_nodes)
  --   local match_type = get_match_type(captured_nodes)
  --   if not match_type then
  --     return
  --   end
  --
  --   ---@type string
  --   local name = vim.treesitter.get_node_text(captured_nodes[match_type .. ".name"], source)
  --   local definition = captured_nodes[match_type .. ".definition"]
  --
  --   return {
  --     type = match_type,
  --     path = file_path,
  --     name = name,
  --     range = { definition:range() },
  --     is_parameterized = captured_nodes["each_property"] and true or false,
  --   }
  -- end

  local positions = lib.treesitter.parse_positions(path, query, {
    nested_tests = true,
  })
  -- vim.notify(
  --   "neotest-vitest > adapter.discover_positions > positions_true: " .. vim.inspect(positions)
  -- )

  -- local positions_false = lib.treesitter.parse_positions(path, query, {
  --   -- WARN: neotest-jest had nested_tests set to false; vitest had it to true
  --   nested_tests = false,
  --   -- build_position = 'require("neotest-vitest").build_position',
  -- })
  -- vim.notify(
  --   "neotest-vitest > adapter.discover_positions > positions_false: "
  --     .. vim.inspect(positions_false)
  -- )

  -- local parameterized_tests_positions =
  --   parameterized_tests.get_parameterized_tests_positions(positions)
  --
  -- if adapter.vitest_test_discovery and #parameterized_tests_positions > 0 then
  --   parameterized_tests.enrich_positions_with_parameterized_tests(
  --     positions:data().path,
  --     parameterized_tests_positions
  --   )
  -- end

  return positions
  -- return lib.treesitter.parse_positions(path, query, { nested_tests = true })
end

---@param path string
---@return string
local function getVitestCommand(path)
  local rootPath = util.find_node_modules_ancestor(path)
  local vitestBinary = util.path.join(rootPath, "node_modules", ".bin", "vitest")

  if util.path.exists(vitestBinary) then
    return vitestBinary
  end

  return "vitest"
end

local vitestConfigPattern = util.root_pattern("{vite,vitest}*.config.{js,ts,mjs,mts}")

---@param path string
---@return string|nil
local function getVitestConfig(path)
  local rootPath = vitestConfigPattern(path)

  if not rootPath then
    return nil
  end

  -- Ordered by config precedence (https://vitest.dev/config/#configuration)
  local possibleVitestConfigNames = {
    "vitest.config.ts",
    "vitest.config.js",
    "vite.config.ts",
    "vite.config.js",
    -- `.mts,.mjs` are sometimes needed (https://vitejs.dev/guide/migration.html#deprecate-cjs-node-api)
    "vitest.config.mts",
    "vitest.config.mjs",
    "vite.config.mts",
    "vite.config.mjs",
  }

  for _, configName in ipairs(possibleVitestConfigNames) do
    local configPath = util.path.join(rootPath, configName)

    if util.path.exists(configPath) then
      -- TEST: monitoring if this is consistent for a couple days
      -- Tested enough that I think we are good... instead I will log if a config is NOT found
      -- vim.notify("neotest-vitest > found vitest config: " .. configPath)
      -- -- more testing
      -- local path_to_test = util.path.join(rootPath, "__tests__", "main", "libs", "fs")
      -- local test_vitest_list_command = parameterized_tests.run_vitest_test_discovery(path_to_test)
      -- vim.notify(
      --   "neotest-vitest > test_vitest_list_command > JSON: "
      --     .. vim.inspect(test_vitest_list_command)
      -- )
      return configPath
    else
      vim.notify("neotest-vitest > vitest config NOT found for some reason: " .. configPath)
    end
  end

  return nil
end

local function escapeTestPattern(s)
  return (
    s:gsub("%(", "%\\(")
      :gsub("%)", "%\\)")
      :gsub("%]", "%\\]")
      :gsub("%[", "%\\[")
      :gsub("%*", "%\\*")
      :gsub("%+", "%\\+")
      :gsub("%-", "%\\-")
      :gsub("%?", "%\\?")
      :gsub("%$", "%\\$")
      :gsub("%^", "%\\^")
      :gsub("%/", "%\\/")
  )
end

local function get_strategy_config(strategy, command, cwd)
  local config = {
    dap = function()
      return {
        name = "Debug Vitest Tests",
        type = "pwa-node",
        request = "launch",
        args = { unpack(command, 2) },
        runtimeExecutable = command[1],
        console = "integratedTerminal",
        internalConsoleOptions = "neverOpen",
        cwd = cwd or "${workspaceFolder}",
      }
    end,
  }
  if config[strategy] then
    return config[strategy]()
  end
end

local function getEnv(specEnv)
  return specEnv
end

---@param path string
---@return string|nil
local function getCwd(path)
  return nil
end

local function cleanAnsi(s)
  return s:gsub("\x1b%[%d+;%d+;%d+;%d+;%d+m", "")
    :gsub("\x1b%[%d+;%d+;%d+;%d+m", "")
    :gsub("\x1b%[%d+;%d+;%d+m", "")
    :gsub("\x1b%[%d+;%d+m", "")
    :gsub("\x1b%[%d+m", "")
end

local function parsed_json_to_results(data, output_file, consoleOut)
  -- vim.notify("neotest-vitest > parsed_json_to_results > data: " .. vim.inspect(data))
  local tests = {}

  for _, testResult in pairs(data.testResults) do
    local testFn = testResult.name

    local is_windows = string.match(vim.uv.os_uname().version, "Windows")
    if is_windows then
      -- NOTE: here is the biggest fix
      -- for windows replace front slashes with a single escaped backslash (means two backslashes)
      -- the reason is later when setting `tests[keyid] = { ... }` the act of setting a
      -- string as the key of the table will escape all the backslashes again.
      -- We ultimately want 2 backslashes at the end of the day and not 4.
      -- vim.fs.normalize() first makes consistent all forward slashes
      testFn = vim.fs.normalize(testFn)
      -- now replace all forward slashes with a single escaped (two) backslashes
      testFn = testFn:gsub("/", "\\")
    end

    for _, assertionResult in pairs(testResult.assertionResults) do
      local status, name = assertionResult.status, assertionResult.title

      if name == nil then
        logger.error("Failed to find parsed test result ", assertionResult)
        return {}
      end

      local keyid = testFn

      for _, value in ipairs(assertionResult.ancestorTitles) do
        if value ~= "" then
          keyid = keyid .. "::" .. value
        end
      end

      keyid = keyid .. "::" .. name

      if status == "pending" or status == "todo" then
        status = "skipped"
      end

      tests[keyid] = {
        status = status,
        short = name .. ": " .. status,
        output = consoleOut,
        location = assertionResult.location,
      }

      if not vim.tbl_isempty(assertionResult.failureMessages) then
        local errors = {}

        for i, failMessage in ipairs(assertionResult.failureMessages) do
          local msg = cleanAnsi(failMessage)

          errors[i] = {
            line = (assertionResult.location and assertionResult.location.line - 1 or nil),
            column = (assertionResult.location and assertionResult.location.column or nil),
            message = msg,
          }

          tests[keyid].short = tests[keyid].short .. "\n" .. msg
        end

        tests[keyid].errors = errors
      end
    end
  end

  -- vim.notify("neotest-vitest > parsed_json_to_results > results: " .. vim.inspect(tests))

  return tests
end

---@param args neotest.RunArgs
---@return neotest.RunSpec | nil
function adapter.build_spec(args)
  local results_path = async.fn.tempname() .. ".json"
  local tree = args.tree

  if not tree then
    return
  end

  local pos = args.tree:data()
  local testNamePattern = ".*"

  if pos.type == "test" then
    testNamePattern = escapeTestPattern(pos.name) .. "$"
  end

  if pos.type == "namespace" then
    testNamePattern = "^ " .. escapeTestPattern(pos.name)
  end

  local binary = args.vitestCommand or getVitestCommand(pos.path)
  local config = getVitestConfig(pos.path) or "vitest.config.js"
  -- vim.notify("adapter.build_spec > binary to use: " .. binary)
  -- vim.notify("adapter.build_spec > config to use: " .. config)
  local command = vim.split(binary, "%s+")

  if util.path.exists(config) then
    -- only use config if available
    table.insert(command, "--config=" .. config)
  end

  vim.list_extend(command, {
    "--watch=false",
    "--reporter=verbose",
    "--reporter=json",
    "--outputFile=" .. results_path,
    "--testNamePattern=" .. testNamePattern,
    vim.fs.normalize(pos.path),
  })

  -- vim.notify("adapter.build_spec > command: " .. vim.inspect(command))

  local cwd = getCwd(pos.path)

  -- creating empty file for streaming results
  lib.files.write(results_path, "")
  local stream_data, stop_stream = util.stream(results_path)

  return {
    command = command,
    cwd = cwd,
    context = {
      results_path = results_path,
      file = pos.path,
      stop_stream = stop_stream,
    },
    stream = function()
      return function()
        local new_results = stream_data()

        if not new_results or new_results == "" then
          return {}
        end

        local ok, parsed = pcall(vim.json.decode, new_results, { luanil = { object = true } })

        if not ok or not parsed.testResults then
          return {}
        end

        return parsed_json_to_results(parsed, results_path, nil)
      end
    end,
    strategy = get_strategy_config(args.strategy, command, cwd),
    env = getEnv(args[2] and args[2].env or {}),
  }
end

---@async
---@param spec neotest.RunSpec
---@return neotest.Result[]
function adapter.results(spec, b, tree)
  spec.context.stop_stream()

  local output_file = spec.context.results_path

  local success, data = pcall(lib.files.read, output_file)

  if not success then
    logger.error("No test output file found ", output_file)
    return {}
  end

  -- vim.notify("neotest-vitest > adapter.results > data: " .. data)

  local ok, parsed = pcall(vim.json.decode, data, { luanil = { object = true } })

  if not ok then
    logger.error("Failed to parse test output json ", output_file)
    return {}
  end
  local results = parsed_json_to_results(parsed, output_file, b.output)

  -- vim.notify("neotest-vitest > adapter.results > REAL results: " .. vim.inspect(results))

  return results
end

local is_callable = function(obj)
  return type(obj) == "function" or (type(obj) == "table" and obj.__call)
end

setmetatable(adapter, {
  ---@param opts neotest.VitestOptions
  __call = function(_, opts)
    if is_callable(opts.vitestCommand) then
      getVitestCommand = opts.vitestCommand
    elseif opts.vitestCommand then
      getVitestCommand = function()
        return opts.vitestCommand
      end
    end

    if is_callable(opts.vitestConfigFile) then
      getVitestConfig = opts.vitestConfigFile
    elseif opts.vitestConfigFile then
      getVitestConfig = function()
        return opts.vitestConfigFile
      end
    end

    if is_callable(opts.env) then
      getEnv = opts.env
    elseif opts.env then
      getEnv = function(specEnv)
        return vim.tbl_extend("force", opts.env, specEnv)
      end
    end

    if is_callable(opts.cwd) then
      getCwd = opts.cwd
    elseif opts.cwd then
      getCwd = function()
        return opts.cwd
      end
    end

    if is_callable(opts.filter_dir) then
      adapter.filter_dir = opts.filter_dir
    end

    if is_callable(opts.is_test_file) then
      adapter.is_test_file = function(file_path)
        return hasVitestDependency(file_path) and opts.is_test_file(file_path)
      end
    end

    return adapter
  end,
})

return adapter
