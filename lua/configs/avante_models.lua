-- Per-user model registry for the local opencode-gateway provider.
--
-- Model ids are deliberately not hardcoded in this repository. They live in
-- ~/.config/avante.nvim/gateway-models.json and are managed from Vim:
--
--   :AvanteModel add [id]     add an id (no id: pick from the gateway)
--   :AvanteModel set [id]     choose the active model
--   :AvanteModel remove [id]  drop an id
--   :AvanteModel list         show the list, active model marked with "*"
--
-- The JSON shape is { "model": "<id>", "models": ["<id>", ...] }. It can also
-- be edited by hand.

local M = {}

M.provider = "opencode_gateway"
M.endpoint = "http://127.0.0.1:12315/v1"

local function store_path()
    return vim.fs.joinpath(vim.fn.expand("~"), ".config", "avante.nvim", "gateway-models.json")
end

local function avante_state_path()
    return vim.fs.joinpath(vim.fn.expand("~"), ".config", "avante.nvim", "config.json")
end

local function notify(msg, level)
    vim.notify("avante: " .. msg, level or vim.log.levels.INFO)
end

local function read_state()
    local state = { models = {} }
    local path = store_path()
    local file = io.open(path, "r")
    if not file then
        return state
    end

    local content = file:read("*a")
    file:close()

    local ok, data = pcall(vim.json.decode, content)
    if not ok or type(data) ~= "table" then
        notify("cannot parse " .. path .. "; starting with an empty model list", vim.log.levels.WARN)
        return state
    end

    if type(data.models) == "table" then
        for _, id in ipairs(data.models) do
            if type(id) == "string" and id ~= "" and not vim.tbl_contains(state.models, id) then
                table.insert(state.models, id)
            end
        end
    end

    if type(data.model) == "string" and data.model ~= "" then
        state.model = data.model
        if not vim.tbl_contains(state.models, data.model) then
            table.insert(state.models, data.model)
        end
    end

    return state
end

M.state = read_state()

---Read the user's model list. Returns copies so callers (avante) cannot
---mutate the registry by accident.
---@return { model?: string, models: string[] }
function M.load()
    M.state = read_state()
    return { model = M.state.model, models = vim.deepcopy(M.state.models) }
end

local function write_state()
    local path = store_path()
    vim.fn.mkdir(vim.fs.dirname(path), "p")

    local tmp = path .. ".tmp"
    local file, err = io.open(tmp, "w")
    if not file then
        notify("cannot write " .. tmp .. ": " .. tostring(err), vim.log.levels.ERROR)
        return false
    end

    file:write(vim.json.encode({ model = M.state.model, models = M.state.models }))
    file:close()

    local ok, rename_err = vim.uv.fs_rename(tmp, path)
    if not ok then
        notify("cannot replace " .. path .. ": " .. tostring(rename_err), vim.log.levels.ERROR)
        return false
    end

    return true
end

-- Push the registry into both the live provider table (used for requests) and
-- the option table (read by the model picker).
local function apply()
    local ok_config, Config = pcall(require, "avante.config")
    if not ok_config then
        return
    end
    local ok_providers, Providers = pcall(require, "avante.providers")
    if not ok_providers then
        return
    end

    -- Assign directly: tbl_deep_extend (used by Config.override) keeps the old
    -- value when the new one is nil, and clearing the model has to remove it.
    local options = Config._options and Config._options.providers and Config._options.providers[M.provider]
    if options then
        options.model = M.state.model
        options.model_names = vim.deepcopy(M.state.models)
    end

    local provider = Providers[M.provider]
    if provider then
        provider.model = M.state.model
        provider.model_names = vim.deepcopy(M.state.models)
    end

    Config.override({ provider = M.provider })

    if M.state.model then
        Config.save_last_model(M.state.model, M.provider)
    else
        -- Do not let avante resurrect a model the user just removed.
        local file = io.open(avante_state_path(), "r")
        if file then
            local content = file:read("*a")
            file:close()
            local ok, data = pcall(vim.json.decode, content)
            if ok and type(data) == "table" and data.last_provider == M.provider then
                os.remove(avante_state_path())
            end
        end
    end

    local sidebar = require("avante").get()
    if sidebar and sidebar:is_open() then
        sidebar:render_result()
    end
end

local function add_model(id)
    if not id or id == "" then
        return
    end

    if vim.tbl_contains(M.state.models, id) then
        if not M.state.model then
            M.state.model = id
            if write_state() then
                apply()
            end
            notify("active model: " .. id)
        else
            notify(id .. " is already in the list; use :AvanteModel set to activate it")
        end
        return
    end

    table.insert(M.state.models, id)
    if not M.state.model then
        M.state.model = id
    end

    if write_state() then
        apply()
        notify("added " .. id .. (M.state.model == id and " (active)" or ""))
    end
end

local function set_model(id)
    if not id or id == "" then
        return
    end
    if not vim.tbl_contains(M.state.models, id) then
        table.insert(M.state.models, id)
    end

    M.state.model = id
    if write_state() then
        apply()
        notify("active model: " .. id)
    end
end

local function remove_model(id)
    local index
    for i, model_id in ipairs(M.state.models) do
        if model_id == id then
            index = i
            break
        end
    end
    if not index then
        notify(id .. " is not in the list", vim.log.levels.WARN)
        return
    end

    table.remove(M.state.models, index)
    if M.state.model == id then
        M.state.model = M.state.models[1]
    end

    if write_state() then
        apply()
        notify(
            "removed " .. id
                .. (M.state.model and ("; active model: " .. M.state.model) or "; no active model")
        )
    end
end

local function list_models()
    if #M.state.models == 0 then
        notify("no models configured; add one with :AvanteModel add (stored in " .. store_path() .. ")")
        return
    end

    local lines = { "models in " .. store_path() .. ":" }
    for _, id in ipairs(M.state.models) do
        table.insert(lines, (id == M.state.model and "* " or "  ") .. id)
    end
    notify(table.concat(lines, "\n"))
end

local function fetch_gateway_models()
    if vim.fn.executable("curl") ~= 1 then
        return {}
    end

    local result = vim.system({ "curl", "-sS", "-m", "3", M.endpoint .. "/models" }, { text = true }):wait()
    if result.code ~= 0 then
        return {}
    end

    local ok, data = pcall(vim.json.decode, result.stdout or "")
    if not ok or type(data) ~= "table" or type(data.data) ~= "table" then
        return {}
    end

    local ids = {}
    for _, item in ipairs(data.data) do
        if type(item) == "table" and type(item.id) == "string" then
            table.insert(ids, item.id)
        end
    end
    return ids
end

local function input_model(prompt, on_submit)
    vim.ui.input({ prompt = prompt }, function(input)
        if input then
            local id = vim.trim(input)
            if id ~= "" then
                on_submit(id)
            end
        end
    end)
end

local function pick_model(prompt, on_choice)
    if #M.state.models == 0 then
        notify("no models configured; add one with :AvanteModel add", vim.log.levels.WARN)
        return
    end

    vim.ui.select(M.state.models, { prompt = prompt }, function(choice)
        if choice then
            on_choice(choice)
        end
    end)
end

local CUSTOM_ID = "→ type a custom id"

local function add_interactively()
    local ids = fetch_gateway_models()
    if #ids == 0 then
        input_model("Model id: ", add_model)
        return
    end

    table.insert(ids, CUSTOM_ID)
    vim.ui.select(ids, { prompt = "Add model> " }, function(choice)
        if not choice then
            return
        end
        if choice == CUSTOM_ID then
            input_model("Model id: ", add_model)
        else
            add_model(choice)
        end
    end)
end

local SUBCOMMANDS = { "add", "set", "remove", "list" }

local function complete(arg_lead, cmd_line, _)
    local parts = vim.split(cmd_line, "%s+", { trimempty = true })
    local trailing_space = cmd_line:match("%s$") ~= nil

    -- Still completing the subcommand: `:AvanteModel ` or `:AvanteModel ad`.
    if #parts == 1 or (#parts == 2 and not trailing_space) then
        return vim.tbl_filter(function(name) return vim.startswith(name, arg_lead) end, SUBCOMMANDS)
    end

    -- Completing the id argument.
    if parts[2] == "add" or parts[2] == "set" or parts[2] == "remove" then
        return vim.tbl_filter(function(name) return vim.startswith(name, arg_lead) end, M.state.models)
    end

    return {}
end

---@param provider_name? string
---@param endpoint? string
function M.setup_commands(provider_name, endpoint)
    M.provider = provider_name or M.provider
    M.endpoint = endpoint or M.endpoint

    -- avante may have a "last used model" cached from a previous session.
    -- Adopt it into the registry if the user has not chosen anything yet.
    local ok, Config = pcall(require, "avante.config")
    if ok then
        local options = Config._options and Config._options.providers and Config._options.providers[M.provider]
        if options then
            if not M.state.model and type(options.model) == "string" and options.model ~= "" then
                M.state.model = options.model
                if not vim.tbl_contains(M.state.models, options.model) then
                    table.insert(M.state.models, options.model)
                end
                write_state()
            end
            apply()
        end
    end

    -- Re-running the plugin's config (e.g. `:Lazy reload avante.nvim`) must not
    -- fail with "command already exists".
    pcall(vim.api.nvim_del_user_command, "AvanteModel")

    vim.api.nvim_create_user_command("AvanteModel", function(opts)
        local subcommand = opts.fargs[1]
        local id = opts.fargs[2]

        if subcommand == "add" then
            if id then
                add_model(id)
            else
                add_interactively()
            end
        elseif subcommand == "set" then
            if id then
                set_model(id)
            else
                pick_model("Set active model> ", set_model)
            end
        elseif subcommand == "remove" then
            if id then
                remove_model(id)
            else
                pick_model("Remove model> ", remove_model)
            end
        elseif subcommand == "list" or subcommand == nil then
            list_models()
        else
            notify("unknown subcommand: " .. subcommand .. " (add|set|remove|list)", vim.log.levels.WARN)
        end
    end, {
        nargs = "*",
        desc = "Manage opencode_gateway model ids",
        complete = complete,
    })
end

return M
