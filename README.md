# finni.nvim

```
███████╗██╗███╗   ██╗███╗   ██╗██╗   ███╗   ██╗██╗   ██╗██╗███╗   ███╗
██╔════╝██║████╗  ██║████╗  ██║██║   ████╗  ██║██║   ██║██║████╗ ████║
█████╗  ██║██╔██╗ ██║██╔██╗ ██║██║   ██╔██╗ ██║██║   ██║██║██╔████╔██║
██╔══╝  ██║██║╚██╗██║██║╚██╗██║██║   ██║╚██╗██║╚██╗ ██╔╝██║██║╚██╔╝██║
██║     ██║██║ ╚████║██║ ╚████║██║██╗██║ ╚████║ ╚████╔╝ ██║██║ ╚═╝ ██║
╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═══╝╚═╝╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚═╝     ╚═╝
```

Sublime autosessions.

A flexible, project-focused autosession plugin for Neovim,
unbound by the limits of `:mksession`.

## Table of Contents

1. [Features](<#finni-features>)
2. [Dependencies](<#finni-dependencies>)
3. [Setup](<#finni-setup>)
    * [Built-in plugin manager](<#finni-setup-nvim-pack>)
    * [lazy.nvim](<#finni-setup-lazy-nvim>)
4. [Configuration](<#finni-configuration>)
    * [Defaults](<#finni-configuration-defaults>)
    * [`finni.UserConfig` (Class)](<#finni.UserConfig>)
5. [Recipes](<#finni-recipes>)
    * [Tab-scoped Sessions](<#finni-recipes-tab-scoped-sessions>)
    * [Custom Extension](<#finni-recipes-custom-extension>)
6. [API](<#finni-api>)
    * [Manual Sessions](<#finni-api-manual-sessions>)
    * [Autosessions](<#finni-api-autosessions>)
    * [Relevant Types](<#finni-api-relevant-types>)
7. [Extensions](<#finni-extensions>)
    * [Built-in](<#finni-extensions-built-in>)
    * [External](<#finni-extensions-external>)
8. [FAQ](<#finni-faq>)

<a id="finni-features"></a>
## Features
- **Very magic behavior**, but only _if you enable it_:
  - Auto(create|save|restore) **sessions per dir/repo/branch**.
  - Restore tabs, correct window **layout**, loaded **buffers**, cursor positions, buf/win/global **options**.
  - Restore **unwritten buffer modifications** and **undo histories**, including for **unnamed buffers**, similar to Sublime Text.
  - Restore **jumplists** and your current position for each (!) window separately.
  - Restore **changelists** and your current position for all buffers.
  - Restore all **loclists** for all windows, including the currently selected one and your current position in it + loclist windows.
  - Restore all **quickfix** lists, including the currently selected one and your current position in it.
  - Restore buffer-local and global **marks**.
  - Restore cursor positions.
  - Keep (session|project)-specific cmd/search/input/expr/debug **histories**.
  - Autoswitch your session when you `git switch other-branch` or `:cd ../other-project` (for example).
- You're still free to _tweak almost any aspect_ of this magic yourself:
  - Some plugin windows are not restored? Write **custom extensions**.
  - Want a project per directory in `$XDG_CONFIG_HOME`, per `basename`, per day of the week or per current byte of `/dev/random`? Go ahead! :)
  - You can specify/filter/override anything that gets persisted, even per project or session.
- You `:set nomagic`? There's a manual session API as well, purely in Lua and similar to [`resession.nvim`](https://github.com/stevearc/resession.nvim)
  (Finni started by forking it, a heartfelt thank you @stevearc! <3).
- **Tab-scoped** sessions are possible (currently via the manual session API only).

<a id="finni-dependencies"></a>
## Dependencies
* Neovim 0.10+
* [`lewis6991/gitsigns.nvim`](https://github.com/lewis6991/gitsigns.nvim/)  (optional) for autoswitch on branch change

<a id="finni-setup"></a>
## Setup

<a id="finni-setup-nvim-pack"></a>
### Built-in plugin manager
```lua
vim.pack.add("https://github.com/lkubb/finni.nvim")
vim.g.finni_autosession = true -- optionally enable startup autosessions
vim.g.finni_config = { --[[ custom options/overrides ]] }
```

<a id="finni-setup-lazy-nvim"></a>
### lazy.nvim

<a id="finni-setup-lazy-nvim-generally"></a>
#### Generally
```lua
{
  'lkubb/finni.nvim',
  -- This plugin only ever loads as much as needed.
  -- You don't need to manage lazyloading manually.
  lazy = false,
  opts = {
    -- Custom options/overrides.
    -- Note: This ends up in `vim.g.finni_config` (via `finni.setup()`).
    --       Initialization is only triggered if you enable autosession-on-load
    --       and an autosession is defined for the current environment
    --       or once you invoke the Finni Lua API/Ex command.
  },
}
```

<a id="finni-setup-lazy-nvim-autosession-on-startup"></a>
#### Autosession on startup
If you want to trigger autosession mode when Neovim starts, you need to set `g:finni_autosession` **early**:
```lua
{
  'lkubb/finni.nvim',
  init = function()
    vim.g.finni_autosession = true
    vim.g.finni_config = { --[[ custom options/overrides ]] }
  end,
}
```

<a id="finni-configuration"></a>
## Configuration

<a id="finni-configuration-defaults"></a>
### Defaults

```lua
{
  autosession = {
    config = {
      modified = false,
    },
    dir = "finni",
    spec = render_autosession_context,
    workspace = util.git.find_workspace_root,
    project_name = util.auto.workspace_project_map,
    session_name = util.auto.generate_name,
    enabled = function(meta)
      return true
    end,
    load_opts = function(meta)
      return {}
    end,
  },
  extensions = {
    quickfix = {},
  },
  load = {
    detail = true,
    order = "modification_time",
  },
  log = {
    level = "warn",
    format = "[%(level)s %(dtime)s] %(message)s%(src_sep)s[%(src_path)s:%(src_line)s]",
    notify_level = "warn",
    notify_format = "%(message)s",
    notify_opts = { title = "Finni" },
    time_format = "%Y-%m-%d %H:%M:%S",
  },
  session = {
    dir = "session",
    options = {
      "binary",
      "bufhidden",
      "buflisted",
      "cmdheight",
      "diff",
      "filetype",
      "modifiable",
      "previewwindow",
      "readonly",
      "scrollbind",
      "winfixheight",
      "winfixwidth",
    },
    buf_filter = default_buf_filter,
    tab_buf_filter = function(tabpage, bufnr, opts)
      return true
    end,
    modified = "auto",
    autosave_enabled = false,
    autosave_interval = 60,
    autosave_notify = true,
    command_history = "auto",
    search_history = "auto",
    input_history = "auto",
    expr_history = "auto",
    debug_history = "auto",
    jumps = "auto",
    changelist = "auto",
    global_marks = "auto",
    local_marks = "auto",
  },
}
```

<a id="finni.UserConfig"></a>
### `finni.UserConfig` (Class)

User configuration for this plugin.

**Fields:**

* **autosession**? [`finni.UserConfig.autosession`](<#finni.UserConfig.autosession>)\
  Influence autosession behavior and contents

  Table fields:

  * **config**? [`finni.core.Session.InitOpts`](<#finni.core.Session.InitOpts>)\
    Save/load configuration for autosessions
  * **dir**? `string`\
    Name of the directory to store autosession projects in.
    Interpreted relative to `$XDG_STATE_HOME/$NVIM_APPNAME`.
  * **spec**? `fun(cwd: string) -> `[`finni.auto.AutosessionSpec`](<#finni.auto.AutosessionSpec>)`?`
  * **workspace**? `fun(cwd: string) -> (string,boolean)`
  * **project_name**? `fun(workspace: string, git_info: `[`finni.auto.AutosessionSpec.GitInfo`](<#finni.auto.AutosessionSpec.GitInfo>)`?) -> string`
  * **session_name**? `fun(meta: {...}) -> string`
  * **enabled**? `fun(meta: {...}) -> boolean`
  * **load_opts**? `fun(meta: {...}) -> `[`finni.auto.LoadOpts`](<#finni.auto.LoadOpts>)`?`
* **extensions**? `table<string,any>`\
  Configuration for extensions, both Resession ones and those specific to Finni.
  Note: Finni first tries to load specified extensions in `finni.extensions`,
  but falls back to `resession.extension` with a warning. Avoid this overhead
  by specifying `resession_compat = true` in the extension config.
* **load**? [`finni.UserConfig.load`](<#finni.UserConfig.load>)\
  Configure session list information detail and sort order

  Table fields:

  * **detail**? `boolean`\
    Show more detail about the sessions when selecting one to load.
    Disable if it causes lag.
  * **order**? `("modification_time"|"creation_time"|"filename")`\
    Session list order
* **log**? [`finni.UserConfig.log`](<#finni.UserConfig.log>)\
  Configure plugin logging

  Table fields:

  * **level**? `("trace"|"debug"|"info"|"warn"|"error"|"off")`\
    Minimum level to log at. Defaults to `warn`.
  * **notify_level**? `("trace"|"debug"|"info"|"warn"|"error"|"off")`\
    Minimum level to use `vim.notify` for. Defaults to `warn`.
  * **notify_opts**? `table`\
    Options to pass to `vim.notify`. Defaults to `{ title = "Finni" }`
  * **format**? `string`\
    Log line format string. Note that this works like Python's f-strings.
    Defaults to `[%(level)s %(dtime)s] %(message)s%(src_sep)s[%(src_path)s:%(src_line)s]`.
    Available parameters:
    * `level` Uppercase level name
    * `message` Log message
    * `dtime` Formatted date/time string
    * `hrtime` Time in `[ns]` without absolute anchor
    * `src_path` Path to the file that called the log function
    * `src_line` Line in `src_path` that called the log function
    * `src_sep` Whitespace between log line and source of call, 2 tabs for single line, newline + tab for multiline log messages
  * **notify_format**? `string`\
    Same as `format`, but for `vim.notify` message display. Defaults to `%(message)s`.
  * **time_format**? `string`\
    `strftime` format string used for rendering time of call. Defaults to `%Y-%m-%d %H:%M:%S`
  * **handler**? `fun(line: `[`finni.log.Line`](<#finni.log.Line>)`)`
* **session**? [`finni.UserConfig.session`](<#finni.UserConfig.session>)\
  Influence session behavior and contents

  Table fields:

  * **autosave_enabled**? `boolean`\
    When this session is attached, automatically save it in intervals. Defaults to false.
  * **autosave_interval**? `integer`\
    Seconds between autosaves of this session, if enabled. Defaults to 60.
  * **autosave_notify**? `boolean`\
    Trigger a notification when autosaving this session. Defaults to true.
  * **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
    A function that's called when attaching to this session. No global default.
  * **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
    A function that's called when detaching from this session. No global default.
  * **options**? `string[]`\
    Save and restore these neovim (global/buffer/tab/window) options
  * **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
  * **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
  * **modified**? `(boolean|"auto")`\
    Save/load modified buffers and their undo history.
    If set to `auto` (default), does not save, but still restores modified buffers.
  * **jumps**? `boolean`\
    Save/load window-specific jumplists, including current position
    (yes, for **all windows**, not just the active one like with ShaDa).
    If set to `auto` (default), does not save, but still restores saved jumplists.
  * **changelist**? `boolean`\
    Save/load buffer-specific changelist (all buffers) and
    changelist position (visible buffers only).

    **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
    Consider tracking `local_marks` in addition to this.
  * **global_marks**? `boolean`\
    Save/load global marks (A-Z, not 0-9 currently).

    _Only in global sessions._
  * **local_marks**? `boolean`\
    Save/load buffer-specific (local) marks.

    **Note**: Enable this if you track the `changelist`.
  * **search_history**? `(integer|boolean)`\
    Maximum number of search history items to persist. Defaults to false.
    If set to `true`, maps to the `'history'` option.

    _Only in global sessions._
  * **command_history**? `(integer|boolean)`\
    Maximum number of command history items to persist. Defaults to false.
    If set to `true`, maps to the `'history'` option.

    _Only in global sessions._
  * **input_history**? `(integer|boolean)`\
    Maximum number of input history items to persist. Defaults to false.
    If set to `true`, maps to the `'history'` option.

    _Only in global sessions._
  * **expr_history**? `boolean`\
    Persist expression history. Defaults to false.
    **Note**: Cannot set limit (currently), no direct support by neovim.

    _Only in global sessions._
  * **debug_history**? `boolean`\
    Persist debug history. Defaults to false.
    **Note**: Cannot set limit (currently), no direct support by neovim.

    _Only in global sessions._
  * **dir**? `string`\
    Name of the directory to store regular sessions in.
    Interpreted relative to `$XDG_STATE_HOME/$NVIM_APPNAME`.

<a id="finni-recipes"></a>
## Recipes

<a id="finni-recipes-tab-scoped-sessions"></a>
### Tab-scoped Sessions
When saving a session, only save the current tab

```lua
-- Bind `save_tab` instead of `save`
local session = require("finni.session")

vim.keymap.set("n", "<leader>ss", session.save_tab)
vim.keymap.set("n", "<leader>sl", session.load)
vim.keymap.set("n", "<leader>sd", session.delete)
```

This only saves the current tabpage layout, but _all_ of the open buffers.
You can provide a filter to exclude buffers.
For example, if you are using `:tcd` to have tabs open for different directories,
this only saves buffers in the current tabpage directory:

```lua
vim.g.finni_config = {
  tab_buf_filter = function(tabpage, bufnr)
    local dir = vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tabpage))
    -- ensure dir has trailing /
    dir = dir:sub(-1) ~= "/" and dir .. "/" or dir
    return vim.startswith(vim.api.nvim_buf_get_name(bufnr), dir)
  end,
}
```

<a id="finni-recipes-custom-extension"></a>
### Custom Extension
You can save custom session data with your own extension.

To create one, add a file to your runtimepath at `lua/finni/extensions/<myplugin>.lua`.
Add the following contents:

```lua
local M = {}

--- Called when saving a session. Should return necessary state.
---@param opts (resession.Extension.OnSaveOpts & finni.core.snapshot.Context)
---@param buflist finni.core.snapshot.BufList
---@return any
M.on_save = function(opts, buflist)
  return {}
end

--- Called before restoring anything, receives the data returned by `on_save`.
---@param data any Data returned by `on_save`
---@param opts finni.core.snapshot.Context
---@param buflist string[]
M.on_pre_load = function(data)
  -- This is run before the buffers, windows, and tabs are restored
end

--- Called after restoring everything, receives the data returned by `on_save`.
---@param data any Data returned by `on_save`
---@param opts finni.core.snapshot.Context
---@param buflist string[]
M.on_post_load = function(data)
  -- This is run after the buffers, windows, and tabs are restored
end

--- Called when Finni gets configured.
--- This function is optional.
---@param data table Configuration data passed in the config (in `extensions.<extension_name>`)
M.config = function(data)
  -- Optional setup for your extension
end

--- Check if a window is supported by this extension.
--- This function is optional, but if provided `save_win` and `load_win` must
--- also be present.
---@param winid integer
---@param bufnr integer
---@return boolean
M.is_win_supported = function(winid, bufnr)
  return false
end

--- Save data for a window. Called when `is_win_supported` returned true.
--- Note: Finni does not focus tabs or windows during session save,
---       so the current window/buffer will most likely be a different one than `winid`.
---@param winid integer
---@return any
M.save_win = function(winid)
  -- This is used to save the data for a specific window that contains a non-file buffer (e.g. a filetree).
  return {}
end

--- Called after creating a tab's windows with the data from `save_win`.
---@param winid integer
---@param data any
---@param win finni.core.layout.WinInfo
---@return integer? new_winid If the original window has been replaced, return the new ID that should replace it
M.load_win = function(winid, config, win)
  -- Restore the window from the config
end

return M
```

Enable your extension by adding a corresponding key in the `extensions` option:

```lua
vim.g.finni_config = {
  extensions = {
    myplugin = {
      -- This table is passed to M.config(). It can be empty.
    },
  },
}
```

For tab-scoped sessions, the `on_save` and `on_load` methods of extensions are **disabled by default**.
You can force-enable them by setting the `enable_in_tab` option to `true` (it's an inbuilt option respected for all extensions).

```lua
vim.g.finni_config = {
  -- ...
  extensions = {
    myplugin = {
      enable_in_tab = true,
    },
  }
}
```

<a id="finni-api"></a>
## API

<a id="finni-api-manual-sessions"></a>
### Manual Sessions


<a id="finni.session"></a>
#### `finni.session` (Module)

Interactive API, (mostly) compatible with stevearc/resession.nvim.

<a id="finni.session.save()"></a>
##### save(`name`, `opts`)

Save the current global state to disk

**Parameters:**
  * **name**? `string`\
    Name of the global session to save.
    If not provided, takes name of attached one or prompts user.

  * **opts**? `(`[`finni.session.SaveOpts`](<#finni.session.SaveOpts>)` & `[`finni.core.PassthroughOpts`](<#finni.core.PassthroughOpts>)`)`

    Table fields:

    * **dir**? `string`\
      Name of session directory (overrides config.dir)
    * **autosave_enabled**? `boolean`\
      When this session is attached, automatically save it in intervals. Defaults to false.
    * **autosave_interval**? `integer`\
      Seconds between autosaves of this session, if enabled. Defaults to 60.
    * **autosave_notify**? `boolean`\
      Trigger a notification when autosaving this session. Defaults to true.
    * **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
      A function that's called when attaching to this session. No global default.
    * **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
      A function that's called when detaching from this session. No global default.
    * **options**? `string[]`\
      Save and restore these neovim (global/buffer/tab/window) options
    * **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **modified**? `(boolean|"auto")`\
      Save/load modified buffers and their undo history.
      If set to `auto` (default), does not save, but still restores modified buffers.
    * **jumps**? `boolean`\
      Save/load window-specific jumplists, including current position
      (yes, for **all windows**, not just the active one like with ShaDa).
      If set to `auto` (default), does not save, but still restores saved jumplists.
    * **changelist**? `boolean`\
      Save/load buffer-specific changelist (all buffers) and
      changelist position (visible buffers only).

      **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
      Consider tracking `local_marks` in addition to this.
    * **global_marks**? `boolean`\
      Save/load global marks (A-Z, not 0-9 currently).

      _Only in global sessions._
    * **local_marks**? `boolean`\
      Save/load buffer-specific (local) marks.

      **Note**: Enable this if you track the `changelist`.
    * **search_history**? `(integer|boolean)`\
      Maximum number of search history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **command_history**? `(integer|boolean)`\
      Maximum number of command history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **input_history**? `(integer|boolean)`\
      Maximum number of input history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **expr_history**? `boolean`\
      Persist expression history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **debug_history**? `boolean`\
      Persist debug history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **meta**? `table`\
      External data remembered in association with this session. Useful to build on top of the core API.
    * **attach**? `boolean`\
      Attach to/stay attached to session after operation
    * **notify**? `boolean`\
      Notify on success
    * **reset**? `boolean`\
      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.

<a id="finni.session.save_tab()"></a>
##### save_tab(`name`, `opts`)

Save the state of the current tabpage to disk

**Parameters:**
  * **name**? `string`\
    Name of the tabpage session to save.
    If not provided, takes name of attached one in current tabpage or prompts user.

  * **opts**? `(`[`finni.session.SaveOpts`](<#finni.session.SaveOpts>)` & `[`finni.core.PassthroughOpts`](<#finni.core.PassthroughOpts>)`)`

    Table fields:

    * **dir**? `string`\
      Name of session directory (overrides config.dir)
    * **autosave_enabled**? `boolean`\
      When this session is attached, automatically save it in intervals. Defaults to false.
    * **autosave_interval**? `integer`\
      Seconds between autosaves of this session, if enabled. Defaults to 60.
    * **autosave_notify**? `boolean`\
      Trigger a notification when autosaving this session. Defaults to true.
    * **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
      A function that's called when attaching to this session. No global default.
    * **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
      A function that's called when detaching from this session. No global default.
    * **options**? `string[]`\
      Save and restore these neovim (global/buffer/tab/window) options
    * **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **modified**? `(boolean|"auto")`\
      Save/load modified buffers and their undo history.
      If set to `auto` (default), does not save, but still restores modified buffers.
    * **jumps**? `boolean`\
      Save/load window-specific jumplists, including current position
      (yes, for **all windows**, not just the active one like with ShaDa).
      If set to `auto` (default), does not save, but still restores saved jumplists.
    * **changelist**? `boolean`\
      Save/load buffer-specific changelist (all buffers) and
      changelist position (visible buffers only).

      **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
      Consider tracking `local_marks` in addition to this.
    * **global_marks**? `boolean`\
      Save/load global marks (A-Z, not 0-9 currently).

      _Only in global sessions._
    * **local_marks**? `boolean`\
      Save/load buffer-specific (local) marks.

      **Note**: Enable this if you track the `changelist`.
    * **search_history**? `(integer|boolean)`\
      Maximum number of search history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **command_history**? `(integer|boolean)`\
      Maximum number of command history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **input_history**? `(integer|boolean)`\
      Maximum number of input history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **expr_history**? `boolean`\
      Persist expression history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **debug_history**? `boolean`\
      Persist debug history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **meta**? `table`\
      External data remembered in association with this session. Useful to build on top of the core API.
    * **attach**? `boolean`\
      Attach to/stay attached to session after operation
    * **notify**? `boolean`\
      Notify on success
    * **reset**? `boolean`\
      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.

<a id="finni.session.save_all()"></a>
##### save_all(`opts`)

**Parameters:**
  * **opts** `unknown`


<a id="finni.session.load()"></a>
##### load(`name`, `opts`)

Load a session from disk

**Attributes:**
  * note

**Parameters:**
  * **name**? `string`\
    Name of the session to load from session dir.
    If not provided, prompts user.

  * **opts**? `(`[`finni.session.LoadOpts`](<#finni.session.LoadOpts>)` & `[`finni.core.PassthroughOpts`](<#finni.core.PassthroughOpts>)`)`\
    attach? boolean Stay attached to session after loading (default true)
    reset? boolean|"auto" Close everything before loading the session (default "auto")
    silence_errors? boolean Don't error when trying to load a missing session
    dir? string Name of directory to load from (overrides config.dir)

    Table fields:

    * **dir**? `string`\
      Name of session directory (overrides config.dir)
    * **autosave_enabled**? `boolean`\
      When this session is attached, automatically save it in intervals. Defaults to false.
    * **autosave_interval**? `integer`\
      Seconds between autosaves of this session, if enabled. Defaults to 60.
    * **autosave_notify**? `boolean`\
      Trigger a notification when autosaving this session. Defaults to true.
    * **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
      A function that's called when attaching to this session. No global default.
    * **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
      A function that's called when detaching from this session. No global default.
    * **options**? `string[]`\
      Save and restore these neovim (global/buffer/tab/window) options
    * **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **modified**? `(boolean|"auto")`\
      Save/load modified buffers and their undo history.
      If set to `auto` (default), does not save, but still restores modified buffers.
    * **jumps**? `boolean`\
      Save/load window-specific jumplists, including current position
      (yes, for **all windows**, not just the active one like with ShaDa).
      If set to `auto` (default), does not save, but still restores saved jumplists.
    * **changelist**? `boolean`\
      Save/load buffer-specific changelist (all buffers) and
      changelist position (visible buffers only).

      **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
      Consider tracking `local_marks` in addition to this.
    * **global_marks**? `boolean`\
      Save/load global marks (A-Z, not 0-9 currently).

      _Only in global sessions._
    * **local_marks**? `boolean`\
      Save/load buffer-specific (local) marks.

      **Note**: Enable this if you track the `changelist`.
    * **search_history**? `(integer|boolean)`\
      Maximum number of search history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **command_history**? `(integer|boolean)`\
      Maximum number of command history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **input_history**? `(integer|boolean)`\
      Maximum number of input history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **expr_history**? `boolean`\
      Persist expression history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **debug_history**? `boolean`\
      Persist debug history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **meta**? `table`\
      External data remembered in association with this session. Useful to build on top of the core API.
    * **attach**? `boolean`\
      Attach to/stay attached to session after operation
    * **reset**? `(boolean|"auto")`\
      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.
      `auto` resets only for global sessions.
    * **save**? `boolean`\
      Save/override autosave config for affected sessions before the operation
    * **silence_errors**? `boolean`\
      Don't error during this operation

<a id="finni.session.detach()"></a>
##### detach(`target`, `reason`, `opts`)

M.get_current = Manager.get_current
M.get_current_data = Manager.get_current_data

**Parameters:**
  * **target**? `("__global"|"__active"|"__active_tab"|"__all_tabs"|string|integer...)`\
    The scope/session name/tabid to detach from. If unspecified, detaches all sessions.

  * **reason**? `(`[`finni.core.Session.DetachReasonBuiltin`](<#finni.core.Session.DetachReasonBuiltin>)`|string)`\
    Pass a custom reason to detach handlers. Defaults to `request`.

  * **opts**? `(`[`finni.core.Session.DetachOpts`](<#finni.core.Session.DetachOpts>)` & `[`finni.core.PassthroughOpts`](<#finni.core.PassthroughOpts>)`)`

    Table fields:

    * **reset**? `boolean`\
      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.
    * **save**? `boolean`\
      Save/override autosave config for affected sessions before the operation

**Returns:** **detached** `boolean`\
Whether we detached from any session


<a id="finni.session.list()"></a>
##### list(`opts`)

List all available saved sessions in session dir

**Parameters:**
  * **opts** `unknown`


**Returns:** **sessions_in_dir** `string[]`

<a id="finni.session.delete()"></a>
##### delete(`name`, `opts`)

Delete a saved session from session dir

**Parameters:**
  * **name**? `string`\
    Name of the session. If not provided, prompts user

  * **opts**? `(`[`finni.session.DeleteOpts`](<#finni.session.DeleteOpts>)` & `[`finni.core.PassthroughOpts`](<#finni.core.PassthroughOpts>)`)`

    Table fields:

    * **dir**? `string`\
      Name of session directory (overrides config.dir)
    * **notify**? `boolean`\
      Notify on success
    * **reset**? `boolean`\
      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.
    * **silence_errors**? `boolean`\
      Don't error during this operation

<a id="finni-api-autosessions"></a>
### Autosessions


<a id="finni.auto"></a>
#### `finni.auto` (Module)

<a id="finni.auto.save()"></a>
##### save(`opts`)

Save the currently active autosession.

**Parameters:**
  * **opts**? `(`[`finni.auto.SaveOpts`](<#finni.auto.SaveOpts>)` & `[`finni.core.PassthroughOpts`](<#finni.core.PassthroughOpts>)`)`

    Table fields:

    * **attach**? `boolean`\
      Attach to/stay attached to session after operation
    * **notify**? `boolean`\
      Notify on success
    * **reset**? `boolean`\
      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.

<a id="finni.auto.detach()"></a>
##### detach(`opts`)

Detach from the currently active autosession.
If autosave is enabled, save it. Optionally close **everything**.

**Parameters:**
  * **opts**? `(`[`finni.core.Session.DetachOpts`](<#finni.core.Session.DetachOpts>)` & `[`finni.core.PassthroughOpts`](<#finni.core.PassthroughOpts>)`)`

    Table fields:

    * **reset**? `boolean`\
      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.
    * **save**? `boolean`\
      Save/override autosave config for affected sessions before the operation

<a id="finni.auto.load()"></a>
##### load(`autosession`, `opts`)

Load an autosession.

**Parameters:**
  * **autosession**? `(`[`finni.auto.AutosessionContext`](<#finni.auto.AutosessionContext>)`|string)`\
    The autosession table as rendered by `get_ctx` or cwd to pass to it

  * **opts**? [`finni.auto.LoadOpts`](<#finni.auto.LoadOpts>)

    Table fields:

    * **autosave_enabled**? `boolean`\
      When this session is attached, automatically save it in intervals. Defaults to false.
    * **autosave_interval**? `integer`\
      Seconds between autosaves of this session, if enabled. Defaults to 60.
    * **autosave_notify**? `boolean`\
      Trigger a notification when autosaving this session. Defaults to true.
    * **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
      A function that's called when attaching to this session. No global default.
    * **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
      A function that's called when detaching from this session. No global default.
    * **options**? `string[]`\
      Save and restore these neovim (global/buffer/tab/window) options
    * **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **modified**? `(boolean|"auto")`\
      Save/load modified buffers and their undo history.
      If set to `auto` (default), does not save, but still restores modified buffers.
    * **jumps**? `boolean`\
      Save/load window-specific jumplists, including current position
      (yes, for **all windows**, not just the active one like with ShaDa).
      If set to `auto` (default), does not save, but still restores saved jumplists.
    * **changelist**? `boolean`\
      Save/load buffer-specific changelist (all buffers) and
      changelist position (visible buffers only).

      **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
      Consider tracking `local_marks` in addition to this.
    * **global_marks**? `boolean`\
      Save/load global marks (A-Z, not 0-9 currently).

      _Only in global sessions._
    * **local_marks**? `boolean`\
      Save/load buffer-specific (local) marks.

      **Note**: Enable this if you track the `changelist`.
    * **search_history**? `(integer|boolean)`\
      Maximum number of search history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **command_history**? `(integer|boolean)`\
      Maximum number of command history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **input_history**? `(integer|boolean)`\
      Maximum number of input history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **expr_history**? `boolean`\
      Persist expression history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **debug_history**? `boolean`\
      Persist debug history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **meta**? `table`\
      External data remembered in association with this session. Useful to build on top of the core API.
    * **attach**? `boolean`\
      Attach to/stay attached to session after operation
    * **save**? `boolean`\
      Save/override autosave config for affected sessions before the operation
    * **reset**? `(boolean|"auto")`\
      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.
      `auto` resets only for global sessions.
    * **silence_errors**? `boolean`\
      Don't error during this operation

<a id="finni.auto.reload()"></a>
##### reload()

If an autosession is active, save it and detach.
Then try to start a new one.

<a id="finni.auto.start()"></a>
##### start(`cwd`, `opts`)

Start Finni:
1. If the current working directory has an associated project and session,
closes everything and loads that session.
2. In any case, start monitoring for directory or branch changes.

**Parameters:**
  * **cwd**? `string`\
    Working directory to switch to before starting autosession. Defaults to nvim's process' cwd.

  * **opts**? [`finni.auto.LoadOpts`](<#finni.auto.LoadOpts>)

    Table fields:

    * **autosave_enabled**? `boolean`\
      When this session is attached, automatically save it in intervals. Defaults to false.
    * **autosave_interval**? `integer`\
      Seconds between autosaves of this session, if enabled. Defaults to 60.
    * **autosave_notify**? `boolean`\
      Trigger a notification when autosaving this session. Defaults to true.
    * **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
      A function that's called when attaching to this session. No global default.
    * **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
      A function that's called when detaching from this session. No global default.
    * **options**? `string[]`\
      Save and restore these neovim (global/buffer/tab/window) options
    * **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **modified**? `(boolean|"auto")`\
      Save/load modified buffers and their undo history.
      If set to `auto` (default), does not save, but still restores modified buffers.
    * **jumps**? `boolean`\
      Save/load window-specific jumplists, including current position
      (yes, for **all windows**, not just the active one like with ShaDa).
      If set to `auto` (default), does not save, but still restores saved jumplists.
    * **changelist**? `boolean`\
      Save/load buffer-specific changelist (all buffers) and
      changelist position (visible buffers only).

      **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
      Consider tracking `local_marks` in addition to this.
    * **global_marks**? `boolean`\
      Save/load global marks (A-Z, not 0-9 currently).

      _Only in global sessions._
    * **local_marks**? `boolean`\
      Save/load buffer-specific (local) marks.

      **Note**: Enable this if you track the `changelist`.
    * **search_history**? `(integer|boolean)`\
      Maximum number of search history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **command_history**? `(integer|boolean)`\
      Maximum number of command history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **input_history**? `(integer|boolean)`\
      Maximum number of input history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **expr_history**? `boolean`\
      Persist expression history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **debug_history**? `boolean`\
      Persist debug history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **meta**? `table`\
      External data remembered in association with this session. Useful to build on top of the core API.
    * **attach**? `boolean`\
      Attach to/stay attached to session after operation
    * **save**? `boolean`\
      Save/override autosave config for affected sessions before the operation
    * **reset**? `(boolean|"auto")`\
      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.
      `auto` resets only for global sessions.
    * **silence_errors**? `boolean`\
      Don't error during this operation

<a id="finni.auto.stop()"></a>
##### stop()

Stop Finni:
1. If we're inside an active autosession, save it and detach.
Keep buffers/windows/tabs etc. by default.
2. In any case, stop monitoring for directory or branch changes.

<a id="finni.auto.reset()"></a>
##### reset(`opts`)

Delete the currently active autosession. Close **everything**.
Attempt to start a new autosession (optionally).

**Parameters:**
  * **opts**? [`finni.auto.ResetOpts`](<#finni.auto.ResetOpts>)

    Table fields:

    * **silence_errors**? `boolean`\
      Don't error during this operation
    * **reset**? `boolean`\
      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.
    * **notify**? `boolean`\
      Notify on success
    * **cwd**? `(string|true)`\
      Path to a directory associated with the session to reset
      instead of current one. Set this to `true` to use nvim's current global CWD.
    * **reload**? `boolean`\
      Attempt to restart a new autosession after reset. Defaults to true.

<a id="finni.auto.reset_project()"></a>
##### reset_project(`opts`)

Remove all autosessions associated with a project.
If the target is the active project, reset current session as well and close **everything**.

**Parameters:**
  * **opts**? [`finni.auto.ResetProjectOpts`](<#finni.auto.ResetProjectOpts>)

    Table fields:

    * **name**? `string`\
      Specify the project to reset. If unspecified, resets active project, if available.
    * **force**? `boolean`\
      Force recursive deletion of project dir outside of configured root

<a id="finni.auto.list()"></a>
##### list(`opts`)

List autosessions associated with a project.

**Parameters:**
  * **opts**? [`finni.auto.ListOpts`](<#finni.auto.ListOpts>)\
    Specify the project to list.
    If unspecified, lists active project, if available.

    Table fields:

    * **cwd**? `string`\
      Path to a directory associated with the project to list
    * **project_dir**? `string`\
      Path to the project session dir
    * **project_name**? `string`\
      Name of the project

**Returns:** **session_names** `string[]`\
List of known sessions associated with project


<a id="finni.auto.list_projects()"></a>
##### list_projects(`opts`)

List all known projects.

**Parameters:**
  * **opts**? [`finni.auto.ListProjectOpts`](<#finni.auto.ListProjectOpts>)

    Table fields:

    * **with_sessions**? `boolean`\
      Additionally list all known sessions for each listed project. Defaults to false.

**Returns:** `string[]`

<a id="finni.auto.migrate_projects()"></a>
##### migrate_projects(`opts`)

Dev helper currently (beware: unstable/inefficient).
When changing the mapping from workspace to project name, all previously
saved states would be lost. This tries to migrate state data to the new mapping,
cleans projects whose cwd does not exist anymore or which are disabled
Caution! This does not account for projects with multiple associated directories/sessions!
Checks the first session's cwd/enabled state only!

**Parameters:**
  * **opts**? [`finni.auto.MigrateProjectsOpts`](<#finni.auto.MigrateProjectsOpts>)\
    Options for migration. You need to pass `{dry_run = false}`
    for this function to have an effect.

    Table fields:

    * **dry_run**? `boolean`\
      Don't execute the migration, only show what would have happened.
      Defaults to true, meaning you need to explicitly set this to `false` to have an effect.
    * **old_root**? `string`\
      If the value of `autosession.dir` has changed, the old value.
      Defaults to `autosession.dir`.

**Returns:** **migration_result** `table<("broken"|"missing"|"skipped"|"migrated"...),table[]>`

<a id="finni.auto.info()"></a>
##### info(`opts`)

Return information about the currently active session.
Includes autosession information, if it is an autosession.

**Parameters:**
  * **opts**? `{ with_snapshot: boolean? }`

    Table fields:

    * **with_snapshot**? `boolean`

**Returns:** **active_info**? [`finni.auto.ActiveAutosessionInfo`](<#finni.auto.ActiveAutosessionInfo>)\
Information about the active session, even if not an autosession.
Always includes snapshot configuration, session meta config and
whether it is an autosession. For autosessions, also includes
autosession config.


<a id="finni-api-relevant-types"></a>
### Relevant Types


<a id="finni.auto.ActiveAutosessionInfo"></a>
#### `finni.auto.ActiveAutosessionInfo` (Class)

**Fields:**

* **session_file** `string`\
  Path to the session file
* **state_dir** `string`\
  Path to the directory holding session-associated data
* **context_dir** `string`\
  Directory for shared state between all sessions in the same context
  (`dir` for manual sessions, project dir for autosessions)
* **autosave_enabled** `boolean`\
  When this session is attached, automatically save it in intervals. Defaults to false.
* **autosave_interval** `integer`\
  Seconds between autosaves of this session, if enabled. Defaults to 60.
* **name** `string`\
  Name of the session
* **tab_scoped** `boolean`\
  Whether the session is tab-scoped
* **is_autosession** `boolean`\
  Whether this is an autosession or a manual one
* **autosave_notify**? `boolean`\
  Trigger a notification when autosaving this session. Defaults to true.
* **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
  A function that's called when attaching to this session. No global default.
* **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
  A function that's called when detaching from this session. No global default.
* **meta**? `table`\
  External data remembered in association with this session. Useful to build on top of the core API.
* **options**? `string[]`\
  Save and restore these neovim (global/buffer/tab/window) options
* **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **modified**? `(boolean|"auto")`\
  Save/load modified buffers and their undo history.
  If set to `auto` (default), does not save, but still restores modified buffers.
* **jumps**? `boolean`\
  Save/load window-specific jumplists, including current position
  (yes, for **all windows**, not just the active one like with ShaDa).
  If set to `auto` (default), does not save, but still restores saved jumplists.
* **changelist**? `boolean`\
  Save/load buffer-specific changelist (all buffers) and
  changelist position (visible buffers only).

  **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
  Consider tracking `local_marks` in addition to this.
* **global_marks**? `boolean`\
  Save/load global marks (A-Z, not 0-9 currently).

  _Only in global sessions._
* **local_marks**? `boolean`\
  Save/load buffer-specific (local) marks.

  **Note**: Enable this if you track the `changelist`.
* **search_history**? `(integer|boolean)`\
  Maximum number of search history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **command_history**? `(integer|boolean)`\
  Maximum number of command history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **input_history**? `(integer|boolean)`\
  Maximum number of input history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **expr_history**? `boolean`\
  Persist expression history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **debug_history**? `boolean`\
  Persist debug history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **tabid**? `(`[`finni.core.TabID`](<#finni.core.TabID>)`|true)`\
  Tab number the session is attached to, if any. Can be `true`, which indicates it's a
  tab-scoped session that has not been restored yet - although not when requesting via the API
* **autosession_config**? [`finni.auto.AutosessionContext`](<#finni.auto.AutosessionContext>)\
  WHen this is an autosession, the internal configuration that was rendered.

  Table fields:

  * **project** [`finni.auto.AutosessionSpec.ProjectInfo`](<#finni.auto.AutosessionSpec.ProjectInfo>)\
    Information about the project the session belongs to
  * **root** `string`\
    The top level directory for this session (workspace root).
    Usually equals the project root, but can be different when git worktrees are used.
  * **name** `string`\
    The name of the session
  * **config** [`finni.auto.LoadOpts`](<#finni.auto.LoadOpts>)\
    Session-specific load/autosave options.
  * **cwd** `string`\
    The effective working directory that was determined when loading this auto-session
* **autosession_data**? [`finni.core.Snapshot`](<#finni.core.Snapshot>)\
  The most recent snapshotted state of this named autosession

  Table fields:

  * **buffers** [`finni.core.Snapshot.BufData`](<#finni.core.Snapshot.BufData>)`[]`\
    Buffer-specific data like name, buffer options, local marks, changelist
  * **tabs** [`finni.core.Snapshot.TabData`](<#finni.core.Snapshot.TabData>)`[]`\
    Tab-specific and window layout data, including tab cwd and window-specific jumplists
  * **tab_scoped** `boolean`\
    Whether this snapshot was derived from a single tab
  * **global** [`finni.core.Snapshot.GlobalData`](<#finni.core.Snapshot.GlobalData>)\
    Global snapshot data like process CWD, global options and global marks
  * **modified**? `table<`[`finni.core.BufUUID`](<#finni.core.BufUUID>)`,true?>`\
    List of buffers (identified by internal UUID) whose unsaved modifications
    were backed up in the snapshot
  * **buflist** `string[]`\
    List of named buffers that are referenced somewhere in this snapshot.
    Used to reduce repetition of buffer paths in save file, especially lists of named marks
    (jumplist, quickfix and location lists).

<a id="finni.auto.AutosessionContext"></a>
#### `finni.auto.AutosessionContext` (Class)

**Fields:**

* **project** [`finni.auto.AutosessionSpec.ProjectInfo`](<#finni.auto.AutosessionSpec.ProjectInfo>)\
  Information about the project the session belongs to

  Table fields:

  * **data_dir**? `string`\
    The path of the directory that is used to save autosession data related to this project.
    If unspecified or empty, defaults to `<nvim data stdpath>/<autosession.dir config>/<escaped project name>`.
    Relative paths are made absolute to `<nvim data stdpath>/<autosession.dir config>`.
  * **name** `string`\
    The name of the project
  * **repo**? [`finni.auto.AutosessionSpec.GitInfo`](<#finni.auto.AutosessionSpec.GitInfo>)\
    When the project is defined as a git repository, meta info
* **root** `string`\
  The top level directory for this session (workspace root).
  Usually equals the project root, but can be different when git worktrees are used.
* **name** `string`\
  The name of the session
* **config** [`finni.auto.LoadOpts`](<#finni.auto.LoadOpts>)\
  Session-specific load/autosave options.

  Table fields:

  * **autosave_enabled**? `boolean`\
    When this session is attached, automatically save it in intervals. Defaults to false.
  * **autosave_interval**? `integer`\
    Seconds between autosaves of this session, if enabled. Defaults to 60.
  * **autosave_notify**? `boolean`\
    Trigger a notification when autosaving this session. Defaults to true.
  * **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
    A function that's called when attaching to this session. No global default.
  * **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
    A function that's called when detaching from this session. No global default.
  * **options**? `string[]`\
    Save and restore these neovim (global/buffer/tab/window) options
  * **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
  * **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
  * **modified**? `(boolean|"auto")`\
    Save/load modified buffers and their undo history.
    If set to `auto` (default), does not save, but still restores modified buffers.
  * **jumps**? `boolean`\
    Save/load window-specific jumplists, including current position
    (yes, for **all windows**, not just the active one like with ShaDa).
    If set to `auto` (default), does not save, but still restores saved jumplists.
  * **changelist**? `boolean`\
    Save/load buffer-specific changelist (all buffers) and
    changelist position (visible buffers only).

    **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
    Consider tracking `local_marks` in addition to this.
  * **global_marks**? `boolean`\
    Save/load global marks (A-Z, not 0-9 currently).

    _Only in global sessions._
  * **local_marks**? `boolean`\
    Save/load buffer-specific (local) marks.

    **Note**: Enable this if you track the `changelist`.
  * **search_history**? `(integer|boolean)`\
    Maximum number of search history items to persist. Defaults to false.
    If set to `true`, maps to the `'history'` option.

    _Only in global sessions._
  * **command_history**? `(integer|boolean)`\
    Maximum number of command history items to persist. Defaults to false.
    If set to `true`, maps to the `'history'` option.

    _Only in global sessions._
  * **input_history**? `(integer|boolean)`\
    Maximum number of input history items to persist. Defaults to false.
    If set to `true`, maps to the `'history'` option.

    _Only in global sessions._
  * **expr_history**? `boolean`\
    Persist expression history. Defaults to false.
    **Note**: Cannot set limit (currently), no direct support by neovim.

    _Only in global sessions._
  * **debug_history**? `boolean`\
    Persist debug history. Defaults to false.
    **Note**: Cannot set limit (currently), no direct support by neovim.

    _Only in global sessions._
  * **meta**? `table`\
    External data remembered in association with this session. Useful to build on top of the core API.
  * **attach**? `boolean`\
    Attach to/stay attached to session after operation
  * **save**? `boolean`\
    Save/override autosave config for affected sessions before the operation
  * **reset**? `(boolean|"auto")`\
    When detaching a session in the process, unload associated resources/reset
    everything during the operation when restoring a snapshot.
    `auto` resets only for global sessions.
  * **silence_errors**? `boolean`\
    Don't error during this operation
* **cwd** `string`\
  The effective working directory that was determined when loading this auto-session

<a id="finni.auto.AutosessionSpec"></a>
#### `finni.auto.AutosessionSpec` (Class)

**Fields:**

* **project** [`finni.auto.AutosessionSpec.ProjectInfo`](<#finni.auto.AutosessionSpec.ProjectInfo>)\
  Information about the project the session belongs to

  Table fields:

  * **data_dir**? `string`\
    The path of the directory that is used to save autosession data related to this project.
    If unspecified or empty, defaults to `<nvim data stdpath>/<autosession.dir config>/<escaped project name>`.
    Relative paths are made absolute to `<nvim data stdpath>/<autosession.dir config>`.
  * **name** `string`\
    The name of the project
  * **repo**? [`finni.auto.AutosessionSpec.GitInfo`](<#finni.auto.AutosessionSpec.GitInfo>)\
    When the project is defined as a git repository, meta info
* **root** `string`\
  The top level directory for this session (workspace root).
  Usually equals the project root, but can be different when git worktrees are used.
* **name** `string`\
  The name of the session
* **config** [`finni.auto.LoadOpts`](<#finni.auto.LoadOpts>)\
  Session-specific load/autosave options.

  Table fields:

  * **autosave_enabled**? `boolean`\
    When this session is attached, automatically save it in intervals. Defaults to false.
  * **autosave_interval**? `integer`\
    Seconds between autosaves of this session, if enabled. Defaults to 60.
  * **autosave_notify**? `boolean`\
    Trigger a notification when autosaving this session. Defaults to true.
  * **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
    A function that's called when attaching to this session. No global default.
  * **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
    A function that's called when detaching from this session. No global default.
  * **options**? `string[]`\
    Save and restore these neovim (global/buffer/tab/window) options
  * **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
  * **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
  * **modified**? `(boolean|"auto")`\
    Save/load modified buffers and their undo history.
    If set to `auto` (default), does not save, but still restores modified buffers.
  * **jumps**? `boolean`\
    Save/load window-specific jumplists, including current position
    (yes, for **all windows**, not just the active one like with ShaDa).
    If set to `auto` (default), does not save, but still restores saved jumplists.
  * **changelist**? `boolean`\
    Save/load buffer-specific changelist (all buffers) and
    changelist position (visible buffers only).

    **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
    Consider tracking `local_marks` in addition to this.
  * **global_marks**? `boolean`\
    Save/load global marks (A-Z, not 0-9 currently).

    _Only in global sessions._
  * **local_marks**? `boolean`\
    Save/load buffer-specific (local) marks.

    **Note**: Enable this if you track the `changelist`.
  * **search_history**? `(integer|boolean)`\
    Maximum number of search history items to persist. Defaults to false.
    If set to `true`, maps to the `'history'` option.

    _Only in global sessions._
  * **command_history**? `(integer|boolean)`\
    Maximum number of command history items to persist. Defaults to false.
    If set to `true`, maps to the `'history'` option.

    _Only in global sessions._
  * **input_history**? `(integer|boolean)`\
    Maximum number of input history items to persist. Defaults to false.
    If set to `true`, maps to the `'history'` option.

    _Only in global sessions._
  * **expr_history**? `boolean`\
    Persist expression history. Defaults to false.
    **Note**: Cannot set limit (currently), no direct support by neovim.

    _Only in global sessions._
  * **debug_history**? `boolean`\
    Persist debug history. Defaults to false.
    **Note**: Cannot set limit (currently), no direct support by neovim.

    _Only in global sessions._
  * **meta**? `table`\
    External data remembered in association with this session. Useful to build on top of the core API.
  * **attach**? `boolean`\
    Attach to/stay attached to session after operation
  * **save**? `boolean`\
    Save/override autosave config for affected sessions before the operation
  * **reset**? `(boolean|"auto")`\
    When detaching a session in the process, unload associated resources/reset
    everything during the operation when restoring a snapshot.
    `auto` resets only for global sessions.
  * **silence_errors**? `boolean`\
    Don't error during this operation

<a id="finni.auto.AutosessionSpec.GitInfo"></a>
#### `finni.auto.AutosessionSpec.GitInfo` (Class)

**Fields:**

* **commongitdir** `string`\
  The common git dir, usually equal to gitdir, unless the worktree is not the default workdir
  (e.g. in worktree checkuots of bare repos).
  Then it's the actual repo root and gitdir is <git_common_dir>/worktrees/<worktree_name>
* **gitdir** `string`\
  The repository (or worktree) data path
* **toplevel** `string`\
  The path of the checked out worktree
* **branch**? `string`\
  The branch the worktree has checked out
* **default_branch**? `string`\
  The name of the default branch

<a id="finni.auto.AutosessionSpec.ProjectInfo"></a>
#### `finni.auto.AutosessionSpec.ProjectInfo` (Class)

**Fields:**

* **name** `string`\
  The name of the project
* **data_dir**? `string`\
  The path of the directory that is used to save autosession data related to this project.
  If unspecified or empty, defaults to `<nvim data stdpath>/<autosession.dir config>/<escaped project name>`.
  Relative paths are made absolute to `<nvim data stdpath>/<autosession.dir config>`.
* **repo**? [`finni.auto.AutosessionSpec.GitInfo`](<#finni.auto.AutosessionSpec.GitInfo>)\
  When the project is defined as a git repository, meta info

  Table fields:

  * **commongitdir** `string`\
    The common git dir, usually equal to gitdir, unless the worktree is not the default workdir
    (e.g. in worktree checkuots of bare repos).
    Then it's the actual repo root and gitdir is <git_common_dir>/worktrees/<worktree_name>
  * **gitdir** `string`\
    The repository (or worktree) data path
  * **toplevel** `string`\
    The path of the checked out worktree
  * **branch**? `string`\
    The branch the worktree has checked out
  * **default_branch**? `string`\
    The name of the default branch

<a id="finni.auto.ListOpts"></a>
#### `finni.auto.ListOpts` (Class)

Options for listing autosessions in a project.
`cwd`, `project_dir` and `project_name` are different ways of referencing
a project and only one of them is respected.

**Fields:**

* **cwd**? `string`\
  Path to a directory associated with the project to list
* **project_dir**? `string`\
  Path to the project session dir
* **project_name**? `string`\
  Name of the project

<a id="finni.auto.ListProjectOpts"></a>
#### `finni.auto.ListProjectOpts` (Class)

**Fields:**

* **with_sessions**? `boolean`\
  Additionally list all known sessions for each listed project. Defaults to false.

<a id="finni.auto.LoadOpts"></a>
#### `finni.auto.LoadOpts` (Alias)

**Type:** `(`[`finni.core.Session.InitOptsWithMeta`](<#finni.core.Session.InitOptsWithMeta>)` & `[`finni.SideEffects.Attach`](<#finni.SideEffects.Attach>)` & `[`finni.SideEffects.Save`](<#finni.SideEffects.Save>)` & `[`finni.SideEffects.ResetAuto`](<#finni.SideEffects.ResetAuto>)` & `[`finni.SideEffects.SilenceErrors`](<#finni.SideEffects.SilenceErrors>)` & `[`finni.core.PassthroughOpts`](<#finni.core.PassthroughOpts>)`)`

API options for `auto.load`

**Fields:**

* **autosave_enabled**? `boolean`\
  When this session is attached, automatically save it in intervals. Defaults to false.
* **autosave_interval**? `integer`\
  Seconds between autosaves of this session, if enabled. Defaults to 60.
* **autosave_notify**? `boolean`\
  Trigger a notification when autosaving this session. Defaults to true.
* **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
  A function that's called when attaching to this session. No global default.
* **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
  A function that's called when detaching from this session. No global default.
* **options**? `string[]`\
  Save and restore these neovim (global/buffer/tab/window) options
* **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **modified**? `(boolean|"auto")`\
  Save/load modified buffers and their undo history.
  If set to `auto` (default), does not save, but still restores modified buffers.
* **jumps**? `boolean`\
  Save/load window-specific jumplists, including current position
  (yes, for **all windows**, not just the active one like with ShaDa).
  If set to `auto` (default), does not save, but still restores saved jumplists.
* **changelist**? `boolean`\
  Save/load buffer-specific changelist (all buffers) and
  changelist position (visible buffers only).

  **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
  Consider tracking `local_marks` in addition to this.
* **global_marks**? `boolean`\
  Save/load global marks (A-Z, not 0-9 currently).

  _Only in global sessions._
* **local_marks**? `boolean`\
  Save/load buffer-specific (local) marks.

  **Note**: Enable this if you track the `changelist`.
* **search_history**? `(integer|boolean)`\
  Maximum number of search history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **command_history**? `(integer|boolean)`\
  Maximum number of command history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **input_history**? `(integer|boolean)`\
  Maximum number of input history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **expr_history**? `boolean`\
  Persist expression history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **debug_history**? `boolean`\
  Persist debug history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **meta**? `table`\
  External data remembered in association with this session. Useful to build on top of the core API.
* **attach**? `boolean`\
  Attach to/stay attached to session after operation
* **save**? `boolean`\
  Save/override autosave config for affected sessions before the operation
* **reset**? `(boolean|"auto")`\
  When detaching a session in the process, unload associated resources/reset
  everything during the operation when restoring a snapshot.
  `auto` resets only for global sessions.
* **silence_errors**? `boolean`\
  Don't error during this operation


<a id="finni.auto.MigrateProjectsOpts"></a>
#### `finni.auto.MigrateProjectsOpts` (Class)

**Fields:**

* **dry_run**? `boolean`\
  Don't execute the migration, only show what would have happened.
  Defaults to true, meaning you need to explicitly set this to `false` to have an effect.
* **old_root**? `string`\
  If the value of `autosession.dir` has changed, the old value.
  Defaults to `autosession.dir`.

<a id="finni.auto.ResetOpts"></a>
#### `finni.auto.ResetOpts` (Class)

API options for `auto.reset`

**Fields:**

* **silence_errors**? `boolean`\
  Don't error during this operation
* **reset**? `boolean`\
  When detaching a session in the process, unload associated resources/reset
  everything during the operation when restoring a snapshot.
* **notify**? `boolean`\
  Notify on success
* **cwd**? `(string|true)`\
  Path to a directory associated with the session to reset
  instead of current one. Set this to `true` to use nvim's current global CWD.
* **reload**? `boolean`\
  Attempt to restart a new autosession after reset. Defaults to true.

<a id="finni.auto.ResetProjectOpts"></a>
#### `finni.auto.ResetProjectOpts` (Class)

**Fields:**

* **name**? `string`\
  Specify the project to reset. If unspecified, resets active project, if available.
* **force**? `boolean`\
  Force recursive deletion of project dir outside of configured root

<a id="finni.auto.SaveOpts"></a>
#### `finni.auto.SaveOpts` (Alias)

**Type:** `(`[`finni.SideEffects.Attach`](<#finni.SideEffects.Attach>)` & `[`finni.SideEffects.Notify`](<#finni.SideEffects.Notify>)` & `[`finni.SideEffects.Reset`](<#finni.SideEffects.Reset>)`)`

API options for `auto.save`

**Fields:**

* **attach**? `boolean`\
  Attach to/stay attached to session after operation
* **notify**? `boolean`\
  Notify on success
* **reset**? `boolean`\
  When detaching a session in the process, unload associated resources/reset
  everything during the operation when restoring a snapshot.


<a id="finni.core.ActiveSession"></a>
#### `finni.core.ActiveSession` (Class)

An active (attached) session.

**Fields:**

* **session_file** `string`\
  Path to the session file
* **state_dir** `string`\
  Path to the directory holding session-associated data
* **context_dir** `string`\
  Directory for shared state between all sessions in the same context
  (`dir` for manual sessions, project dir for autosessions)
* **autosave_enabled** `boolean`\
  Autosave this attached session in intervals and when detaching
* **autosave_interval** `integer`\
  Seconds between autosaves of this session, if enabled.
* **name** `string`
* **tab_scoped** `boolean`
* **autosave_notify**? `boolean`\
  Trigger a notification when autosaving this session. Defaults to true.
* **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
  A function that's called when attaching to this session. No global default.
* **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
  A function that's called when detaching from this session. No global default.
* **meta**? `table`\
  External data remembered in association with this session. Useful to build on top of the core API.
* **options**? `string[]`\
  Save and restore these neovim (global/buffer/tab/window) options
* **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **modified**? `(boolean|"auto")`\
  Save/load modified buffers and their undo history.
  If set to `auto` (default), does not save, but still restores modified buffers.
* **jumps**? `boolean`\
  Save/load window-specific jumplists, including current position
  (yes, for **all windows**, not just the active one like with ShaDa).
  If set to `auto` (default), does not save, but still restores saved jumplists.
* **changelist**? `boolean`\
  Save/load buffer-specific changelist (all buffers) and
  changelist position (visible buffers only).

  **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
  Consider tracking `local_marks` in addition to this.
* **global_marks**? `boolean`\
  Save/load global marks (A-Z, not 0-9 currently).

  _Only in global sessions._
* **local_marks**? `boolean`\
  Save/load buffer-specific (local) marks.

  **Note**: Enable this if you track the `changelist`.
* **search_history**? `(integer|boolean)`\
  Maximum number of search history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **command_history**? `(integer|boolean)`\
  Maximum number of command history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **input_history**? `(integer|boolean)`\
  Maximum number of input history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **expr_history**? `boolean`\
  Persist expression history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **debug_history**? `boolean`\
  Persist debug history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **tabid**? [`finni.core.TabID`](<#finni.core.TabID>)

<a id="finni.core.ActiveSession.new()"></a>
##### new(`name`, `session_file`, `state_dir`, `context_dir`, `opts`, `tabid`, `needs_restore`)

**Parameters:**
  * **name** `string`

  * **session_file** `string`

  * **state_dir** `string`

  * **context_dir** `string`

  * **opts** [`finni.core.Session.InitOptsWithMeta`](<#finni.core.Session.InitOptsWithMeta>)

  * **tabid** `true`

  * **needs_restore** `true`


**Returns:** [`finni.core.PendingSession`](<#finni.core.PendingSession>)`<`[`finni.core.Session.TabTarget`](<#finni.core.Session.TabTarget>)`>`

<a id="finni.core.ActiveSession.from_snapshot()"></a>
##### from_snapshot(`name`, `session_file`, `state_dir`, `context_dir`, `opts`)

Create a new session by loading a snapshot, which you need to restore explicitly.

**Parameters:**
  * **name** `string`

  * **session_file** `string`

  * **state_dir** `string`

  * **context_dir** `string`

  * **opts** `(`[`finni.core.Session.InitOptsWithMeta`](<#finni.core.Session.InitOptsWithMeta>)` & `[`finni.SideEffects.SilenceErrors`](<#finni.SideEffects.SilenceErrors>)`)`

    Table fields:

    * **autosave_enabled**? `boolean`\
      When this session is attached, automatically save it in intervals. Defaults to false.
    * **autosave_interval**? `integer`\
      Seconds between autosaves of this session, if enabled. Defaults to 60.
    * **autosave_notify**? `boolean`\
      Trigger a notification when autosaving this session. Defaults to true.
    * **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
      A function that's called when attaching to this session. No global default.
    * **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
      A function that's called when detaching from this session. No global default.
    * **options**? `string[]`\
      Save and restore these neovim (global/buffer/tab/window) options
    * **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **modified**? `(boolean|"auto")`\
      Save/load modified buffers and their undo history.
      If set to `auto` (default), does not save, but still restores modified buffers.
    * **jumps**? `boolean`\
      Save/load window-specific jumplists, including current position
      (yes, for **all windows**, not just the active one like with ShaDa).
      If set to `auto` (default), does not save, but still restores saved jumplists.
    * **changelist**? `boolean`\
      Save/load buffer-specific changelist (all buffers) and
      changelist position (visible buffers only).

      **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
      Consider tracking `local_marks` in addition to this.
    * **global_marks**? `boolean`\
      Save/load global marks (A-Z, not 0-9 currently).

      _Only in global sessions._
    * **local_marks**? `boolean`\
      Save/load buffer-specific (local) marks.

      **Note**: Enable this if you track the `changelist`.
    * **search_history**? `(integer|boolean)`\
      Maximum number of search history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **command_history**? `(integer|boolean)`\
      Maximum number of command history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **input_history**? `(integer|boolean)`\
      Maximum number of input history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **expr_history**? `boolean`\
      Persist expression history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **debug_history**? `boolean`\
      Persist debug history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **meta**? `table`\
      External data remembered in association with this session. Useful to build on top of the core API.
    * **silence_errors**? `boolean`\
      Don't error during this operation

**Returns:**
  * **loaded_session**? [`finni.core.PendingSession`](<#finni.core.PendingSession>)\
    Session object, if the snapshot could be loaded

  * **snapshot**? [`finni.core.Snapshot`](<#finni.core.Snapshot>)\
    Snapshot data, if it could be loaded


<a id="finni.core.ActiveSession:add_hook()"></a>
##### ActiveSession:add_hook(`event`, `hook`)

**Parameters:**
  * **event** `"detach"`

  * **hook** [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)


**Returns:** `self`

<a id="finni.core.ActiveSession:update()"></a>
##### ActiveSession:update(`opts`)

Update modifiable options without attaching/detaching a session

**Parameters:**
  * **opts** [`finni.core.Session.InitOptsWithMeta`](<#finni.core.Session.InitOptsWithMeta>)


**Returns:** **modified** `boolean`\
Indicates whether any config modifications occurred


<a id="finni.core.ActiveSession:restore()"></a>
##### ActiveSession:restore(`opts`, `snapshot`)

Restore a snapshot from disk or memory
It seems emmylua does not pick up this override and infers IdleSession<T> instead.

**Parameters:**
  * **opts**? `(`[`finni.core.Session.RestoreOpts`](<#finni.core.Session.RestoreOpts>)` & `[`finni.core.PassthroughOpts`](<#finni.core.PassthroughOpts>)`)`

    Table fields:

    * **reset**? `boolean`\
      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.
    * **silence_errors**? `boolean`\
      Don't error during this operation
  * **snapshot**? [`finni.core.Snapshot`](<#finni.core.Snapshot>)\
    Snapshot to restore. If unspecified, loads from file.

    Table fields:

    * **buffers** [`finni.core.Snapshot.BufData`](<#finni.core.Snapshot.BufData>)`[]`\
      Buffer-specific data like name, buffer options, local marks, changelist
    * **tabs** [`finni.core.Snapshot.TabData`](<#finni.core.Snapshot.TabData>)`[]`\
      Tab-specific and window layout data, including tab cwd and window-specific jumplists
    * **tab_scoped** `boolean`\
      Whether this snapshot was derived from a single tab
    * **global** [`finni.core.Snapshot.GlobalData`](<#finni.core.Snapshot.GlobalData>)\
      Global snapshot data like process CWD, global options and global marks
    * **modified**? `table<`[`finni.core.BufUUID`](<#finni.core.BufUUID>)`,true?>`\
      List of buffers (identified by internal UUID) whose unsaved modifications
      were backed up in the snapshot
    * **buflist** `string[]`\
      List of named buffers that are referenced somewhere in this snapshot.
      Used to reduce repetition of buffer paths in save file, especially lists of named marks
      (jumplist, quickfix and location lists).

**Returns:**
  * **self** [`finni.core.ActiveSession`](<#finni.core.ActiveSession>)\
    Same object.

  * **success** `boolean`\
    Whether restoration was successful. Only sensible when `silence_errors` is true.


<a id="finni.core.ActiveSession:is_attached()"></a>
##### ActiveSession:is_attached()

I couldn't make TypeGuard<ActiveSession<T>> work properly with method syntax

**Returns:** `TypeGuard<`[`finni.core.ActiveSession`](<#finni.core.ActiveSession>)`>`

<a id="finni.core.ActiveSession:opts()"></a>
##### ActiveSession:opts()

Turn the session object into opts for snapshot restore/save operations

**Returns:** `(`[`finni.core.Session.Init.Paths`](<#finni.core.Session.Init.Paths>)` & `[`finni.core.Session.Init.Autosave`](<#finni.core.Session.Init.Autosave>)` & `[`finni.core.Session.Init.Meta`](<#finni.core.Session.Init.Meta>)` & `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`)`

<a id="finni.core.ActiveSession:info()"></a>
##### ActiveSession:info()

Get information about this session

**Returns:** [`finni.core.ActiveSessionInfo`](<#finni.core.ActiveSessionInfo>)

<a id="finni.core.ActiveSession:delete()"></a>
##### ActiveSession:delete(`opts`)

Delete a saved session

**Parameters:**
  * **opts**? `(`[`finni.SideEffects.Notify`](<#finni.SideEffects.Notify>)` & `[`finni.SideEffects.SilenceErrors`](<#finni.SideEffects.SilenceErrors>)`)`

    Table fields:

    * **notify**? `boolean`\
      Notify on success
    * **silence_errors**? `boolean`\
      Don't error during this operation

<a id="finni.core.ActiveSession:attach()"></a>
##### ActiveSession:attach()

Attach this session. If it was loaded from a snapshot file, you must ensure you restore
the snapshot (`:restore()`) before calling this method.
It's fine to attach an already attached session.

**Returns:** [`finni.core.ActiveSession`](<#finni.core.ActiveSession>)

<a id="finni.core.ActiveSession:save()"></a>
##### ActiveSession:save(`opts`)

Save this session following its configured configuration.
Note: Any save configuration must be applied via `Session.update(opts)` before
callig this method since all session-specific options that might be contained
in `opts` are overridded with ones configured for the session.

**Parameters:**
  * **opts** `unknown`\
    Success notification setting plus options that need to be passed through to pre_save/post_save hooks.


**Returns:** **success** `boolean`

<a id="finni.core.ActiveSession:autosave()"></a>
##### ActiveSession:autosave(`opts`, `force`)

**Parameters:**
  * **opts** `unknown`

  * **force**? `boolean`\
    Force snapshot to be saved, regardless of autosave config


<a id="finni.core.ActiveSession:detach()"></a>
##### ActiveSession:detach(`reason`, `opts`)

Detach from this session. Ensure the session is attached before trying to detach,
otherwise you'll receive an error.
Hint: If you are sure the session should be attached, but still receive an error,
ensure that you call `detach()` on the specific session instance you called `:attach()` on before, not a copy.
@param self ActiveSession<T>

**Parameters:**
  * **reason** `(`[`finni.core.Session.DetachReasonBuiltin`](<#finni.core.Session.DetachReasonBuiltin>)`|string)`\
    A reason for detaching, also passed to detach hooks.
    Only inbuilt reasons influence behavior by default.

  * **opts** `(`[`finni.core.Session.DetachOpts`](<#finni.core.Session.DetachOpts>)` & `[`finni.core.PassthroughOpts`](<#finni.core.PassthroughOpts>)`)`\
    Influence side effects. `reset` removes all associated resources.
    `save` overrides autosave behavior.

    Table fields:

    * **reset**? `boolean`\
      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.
    * **save**? `boolean`\
      Save/override autosave config for affected sessions before the operation

**Returns:** **idle_session** [`finni.core.IdleSession`](<#finni.core.IdleSession>)\
Same data table, but now representing an idle session again.


<a id="finni.core.ActiveSession:forget()"></a>
##### ActiveSession:forget(`self`)

Mark a **tab** session as invalid (i.e. remembered as attached, but its tab is gone).
Removes associated resources, skips autosave.

**Parameters:**
  * **self** [`finni.core.ActiveSession`](<#finni.core.ActiveSession>)`<`[`finni.core.Session.TabTarget`](<#finni.core.Session.TabTarget>)`>`\
    Active **tab** session to forget about. Errors if attempted with global sessions.

    Table fields:

    * **session_file** `string`\
      Path to the session file
    * **state_dir** `string`\
      Path to the directory holding session-associated data
    * **context_dir** `string`\
      Directory for shared state between all sessions in the same context
      (`dir` for manual sessions, project dir for autosessions)
    * **autosave_enabled** `boolean`\
      Autosave this attached session in intervals and when detaching
    * **autosave_interval** `integer`\
      Seconds between autosaves of this session, if enabled.
    * **autosave_notify**? `boolean`\
      Trigger a notification when autosaving this session. Defaults to true.
    * **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
      A function that's called when attaching to this session. No global default.
    * **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
      A function that's called when detaching from this session. No global default.
    * **meta**? `table`\
      External data remembered in association with this session. Useful to build on top of the core API.
    * **options**? `string[]`\
      Save and restore these neovim (global/buffer/tab/window) options
    * **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **modified**? `(boolean|"auto")`\
      Save/load modified buffers and their undo history.
      If set to `auto` (default), does not save, but still restores modified buffers.
    * **jumps**? `boolean`\
      Save/load window-specific jumplists, including current position
      (yes, for **all windows**, not just the active one like with ShaDa).
      If set to `auto` (default), does not save, but still restores saved jumplists.
    * **changelist**? `boolean`\
      Save/load buffer-specific changelist (all buffers) and
      changelist position (visible buffers only).

      **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
      Consider tracking `local_marks` in addition to this.
    * **global_marks**? `boolean`\
      Save/load global marks (A-Z, not 0-9 currently).

      _Only in global sessions._
    * **local_marks**? `boolean`\
      Save/load buffer-specific (local) marks.

      **Note**: Enable this if you track the `changelist`.
    * **search_history**? `(integer|boolean)`\
      Maximum number of search history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **command_history**? `(integer|boolean)`\
      Maximum number of command history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **input_history**? `(integer|boolean)`\
      Maximum number of input history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **expr_history**? `boolean`\
      Persist expression history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **debug_history**? `boolean`\
      Persist debug history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **tab_scoped** `boolean`
    * **tabid**? [`finni.core.TabID`](<#finni.core.TabID>)
    * **name** `string`
    * **_on_attach** [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)`[]`
    * **_on_detach** [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)`[]`
    * **_aug** `integer`\
      Neovim augroup for this session
    * **_timer**? `uv.uv_timer_t`\
      Autosave timer, if enabled
    * **_setup_autosave** `fun(self: `[`finni.core.ActiveSession`](<#finni.core.ActiveSession>)`<`[`finni.core.Session.TabTarget`](<#finni.core.Session.TabTarget>)`>)`

**Returns:** **idle_session** [`finni.core.IdleSession`](<#finni.core.IdleSession>)`<`[`finni.core.Session.TabTarget`](<#finni.core.Session.TabTarget>)`>`

<a id="finni.core.ActiveSessionInfo"></a>
#### `finni.core.ActiveSessionInfo` (Class)

Represents the complete internal state of a session

**Fields:**

* **session_file** `string`\
  Path to the session file
* **state_dir** `string`\
  Path to the directory holding session-associated data
* **context_dir** `string`\
  Directory for shared state between all sessions in the same context
  (`dir` for manual sessions, project dir for autosessions)
* **autosave_enabled** `boolean`\
  When this session is attached, automatically save it in intervals. Defaults to false.
* **autosave_interval** `integer`\
  Seconds between autosaves of this session, if enabled. Defaults to 60.
* **name** `string`\
  Name of the session
* **tab_scoped** `boolean`\
  Whether the session is tab-scoped
* **autosave_notify**? `boolean`\
  Trigger a notification when autosaving this session. Defaults to true.
* **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
  A function that's called when attaching to this session. No global default.
* **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
  A function that's called when detaching from this session. No global default.
* **meta**? `table`\
  External data remembered in association with this session. Useful to build on top of the core API.
* **options**? `string[]`\
  Save and restore these neovim (global/buffer/tab/window) options
* **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **modified**? `(boolean|"auto")`\
  Save/load modified buffers and their undo history.
  If set to `auto` (default), does not save, but still restores modified buffers.
* **jumps**? `boolean`\
  Save/load window-specific jumplists, including current position
  (yes, for **all windows**, not just the active one like with ShaDa).
  If set to `auto` (default), does not save, but still restores saved jumplists.
* **changelist**? `boolean`\
  Save/load buffer-specific changelist (all buffers) and
  changelist position (visible buffers only).

  **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
  Consider tracking `local_marks` in addition to this.
* **global_marks**? `boolean`\
  Save/load global marks (A-Z, not 0-9 currently).

  _Only in global sessions._
* **local_marks**? `boolean`\
  Save/load buffer-specific (local) marks.

  **Note**: Enable this if you track the `changelist`.
* **search_history**? `(integer|boolean)`\
  Maximum number of search history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **command_history**? `(integer|boolean)`\
  Maximum number of command history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **input_history**? `(integer|boolean)`\
  Maximum number of input history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **expr_history**? `boolean`\
  Persist expression history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **debug_history**? `boolean`\
  Persist debug history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **tabid**? `(`[`finni.core.TabID`](<#finni.core.TabID>)`|true)`\
  Tab number the session is attached to, if any. Can be `true`, which indicates it's a
  tab-scoped session that has not been restored yet - although not when requesting via the API

<a id="finni.core.AnonymousMark"></a>
#### `finni.core.AnonymousMark` (Class)

**Fields:**

* **[1]** `integer`\
  Line number
* **[2]** `integer`\
  Column number

<a id="finni.core.BufUUID"></a>
#### `finni.core.BufUUID` (Alias)

**Type:** `string`

An internal UUID that is used to keep track of buffers between snapshot restorations.


<a id="finni.core.FileMark"></a>
#### `finni.core.FileMark` (Class)

**Fields:**

* **[1]** `sub<string,"">`\
  Absolute path to file this mark references
* **[2]** `integer`\
  Line number
* **[3]** `integer`\
  Column number

<a id="finni.core.IdleSession"></a>
#### `finni.core.IdleSession` (Class)

A general session config that can be attached, turning it into an active session.

**Fields:**

* **session_file** `string`\
  Path to the session file
* **state_dir** `string`\
  Path to the directory holding session-associated data
* **context_dir** `string`\
  Directory for shared state between all sessions in the same context
  (`dir` for manual sessions, project dir for autosessions)
* **autosave_enabled** `boolean`\
  When this session is attached, automatically save it in intervals. Defaults to false.
* **autosave_interval** `integer`\
  Seconds between autosaves of this session, if enabled. Defaults to 60.
* **name** `string`
* **tab_scoped** `boolean`
* **autosave_notify**? `boolean`\
  Trigger a notification when autosaving this session. Defaults to true.
* **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
  A function that's called when attaching to this session. No global default.
* **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
  A function that's called when detaching from this session. No global default.
* **meta**? `table`\
  External data remembered in association with this session. Useful to build on top of the core API.
* **options**? `string[]`\
  Save and restore these neovim (global/buffer/tab/window) options
* **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **modified**? `(boolean|"auto")`\
  Save/load modified buffers and their undo history.
  If set to `auto` (default), does not save, but still restores modified buffers.
* **jumps**? `boolean`\
  Save/load window-specific jumplists, including current position
  (yes, for **all windows**, not just the active one like with ShaDa).
  If set to `auto` (default), does not save, but still restores saved jumplists.
* **changelist**? `boolean`\
  Save/load buffer-specific changelist (all buffers) and
  changelist position (visible buffers only).

  **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
  Consider tracking `local_marks` in addition to this.
* **global_marks**? `boolean`\
  Save/load global marks (A-Z, not 0-9 currently).

  _Only in global sessions._
* **local_marks**? `boolean`\
  Save/load buffer-specific (local) marks.

  **Note**: Enable this if you track the `changelist`.
* **search_history**? `(integer|boolean)`\
  Maximum number of search history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **command_history**? `(integer|boolean)`\
  Maximum number of command history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **input_history**? `(integer|boolean)`\
  Maximum number of input history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **expr_history**? `boolean`\
  Persist expression history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **debug_history**? `boolean`\
  Persist debug history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **tabid**? [`finni.core.TabID`](<#finni.core.TabID>)

<a id="finni.core.IdleSession.new()"></a>
##### new(`name`, `session_file`, `state_dir`, `context_dir`, `opts`, `tabid`, `needs_restore`)

**Parameters:**
  * **name** `string`

  * **session_file** `string`

  * **state_dir** `string`

  * **context_dir** `string`

  * **opts** [`finni.core.Session.InitOptsWithMeta`](<#finni.core.Session.InitOptsWithMeta>)

  * **tabid** `true`

  * **needs_restore** `true`


**Returns:** [`finni.core.PendingSession`](<#finni.core.PendingSession>)`<`[`finni.core.Session.TabTarget`](<#finni.core.Session.TabTarget>)`>`

<a id="finni.core.IdleSession.from_snapshot()"></a>
##### from_snapshot(`name`, `session_file`, `state_dir`, `context_dir`, `opts`)

Create a new session by loading a snapshot, which you need to restore explicitly.

**Parameters:**
  * **name** `string`

  * **session_file** `string`

  * **state_dir** `string`

  * **context_dir** `string`

  * **opts** `(`[`finni.core.Session.InitOptsWithMeta`](<#finni.core.Session.InitOptsWithMeta>)` & `[`finni.SideEffects.SilenceErrors`](<#finni.SideEffects.SilenceErrors>)`)`

    Table fields:

    * **autosave_enabled**? `boolean`\
      When this session is attached, automatically save it in intervals. Defaults to false.
    * **autosave_interval**? `integer`\
      Seconds between autosaves of this session, if enabled. Defaults to 60.
    * **autosave_notify**? `boolean`\
      Trigger a notification when autosaving this session. Defaults to true.
    * **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
      A function that's called when attaching to this session. No global default.
    * **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
      A function that's called when detaching from this session. No global default.
    * **options**? `string[]`\
      Save and restore these neovim (global/buffer/tab/window) options
    * **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **modified**? `(boolean|"auto")`\
      Save/load modified buffers and their undo history.
      If set to `auto` (default), does not save, but still restores modified buffers.
    * **jumps**? `boolean`\
      Save/load window-specific jumplists, including current position
      (yes, for **all windows**, not just the active one like with ShaDa).
      If set to `auto` (default), does not save, but still restores saved jumplists.
    * **changelist**? `boolean`\
      Save/load buffer-specific changelist (all buffers) and
      changelist position (visible buffers only).

      **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
      Consider tracking `local_marks` in addition to this.
    * **global_marks**? `boolean`\
      Save/load global marks (A-Z, not 0-9 currently).

      _Only in global sessions._
    * **local_marks**? `boolean`\
      Save/load buffer-specific (local) marks.

      **Note**: Enable this if you track the `changelist`.
    * **search_history**? `(integer|boolean)`\
      Maximum number of search history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **command_history**? `(integer|boolean)`\
      Maximum number of command history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **input_history**? `(integer|boolean)`\
      Maximum number of input history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **expr_history**? `boolean`\
      Persist expression history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **debug_history**? `boolean`\
      Persist debug history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **meta**? `table`\
      External data remembered in association with this session. Useful to build on top of the core API.
    * **silence_errors**? `boolean`\
      Don't error during this operation

**Returns:**
  * **loaded_session**? [`finni.core.PendingSession`](<#finni.core.PendingSession>)\
    Session object, if the snapshot could be loaded

  * **snapshot**? [`finni.core.Snapshot`](<#finni.core.Snapshot>)\
    Snapshot data, if it could be loaded


<a id="finni.core.IdleSession:add_hook()"></a>
##### IdleSession:add_hook(`event`, `hook`)

**Parameters:**
  * **event** `"detach"`

  * **hook** [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)


**Returns:** `self`

<a id="finni.core.IdleSession:update()"></a>
##### IdleSession:update(`opts`)

Update modifiable options without attaching/detaching a session

**Parameters:**
  * **opts** [`finni.core.Session.InitOptsWithMeta`](<#finni.core.Session.InitOptsWithMeta>)


**Returns:** **modified** `boolean`\
Indicates whether any config modifications occurred


<a id="finni.core.IdleSession:restore()"></a>
##### IdleSession:restore(`opts`, `snapshot`)

Restore a snapshot from disk or memory

**Parameters:**
  * **opts**? `(`[`finni.core.Session.RestoreOpts`](<#finni.core.Session.RestoreOpts>)` & `[`finni.core.PassthroughOpts`](<#finni.core.PassthroughOpts>)`)`

    Table fields:

    * **reset**? `boolean`\
      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.
    * **silence_errors**? `boolean`\
      Don't error during this operation
  * **snapshot**? [`finni.core.Snapshot`](<#finni.core.Snapshot>)\
    Snapshot data to restore. If unspecified, loads from file.

    Table fields:

    * **buffers** [`finni.core.Snapshot.BufData`](<#finni.core.Snapshot.BufData>)`[]`\
      Buffer-specific data like name, buffer options, local marks, changelist
    * **tabs** [`finni.core.Snapshot.TabData`](<#finni.core.Snapshot.TabData>)`[]`\
      Tab-specific and window layout data, including tab cwd and window-specific jumplists
    * **tab_scoped** `boolean`\
      Whether this snapshot was derived from a single tab
    * **global** [`finni.core.Snapshot.GlobalData`](<#finni.core.Snapshot.GlobalData>)\
      Global snapshot data like process CWD, global options and global marks
    * **modified**? `table<`[`finni.core.BufUUID`](<#finni.core.BufUUID>)`,true?>`\
      List of buffers (identified by internal UUID) whose unsaved modifications
      were backed up in the snapshot
    * **buflist** `string[]`\
      List of named buffers that are referenced somewhere in this snapshot.
      Used to reduce repetition of buffer paths in save file, especially lists of named marks
      (jumplist, quickfix and location lists).

**Returns:**
  * **self** [`finni.core.IdleSession`](<#finni.core.IdleSession>)\
    The object itself, but now attachable

  * **success** `boolean`\
    Whether restoration was successful. Only sensible when `silence_errors` is true.


<a id="finni.core.IdleSession:is_attached()"></a>
##### IdleSession:is_attached()

I couldn't make TypeGuard<ActiveSession<T>> work properly with method syntax

**Returns:** `TypeGuard<`[`finni.core.ActiveSession`](<#finni.core.ActiveSession>)`>`

<a id="finni.core.IdleSession:opts()"></a>
##### IdleSession:opts()

Turn the session object into opts for snapshot restore/save operations

**Returns:** `(`[`finni.core.Session.Init.Paths`](<#finni.core.Session.Init.Paths>)` & `[`finni.core.Session.Init.Autosave`](<#finni.core.Session.Init.Autosave>)` & `[`finni.core.Session.Init.Meta`](<#finni.core.Session.Init.Meta>)` & `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`)`

<a id="finni.core.IdleSession:info()"></a>
##### IdleSession:info()

Get information about this session

**Returns:** [`finni.core.ActiveSessionInfo`](<#finni.core.ActiveSessionInfo>)

<a id="finni.core.IdleSession:delete()"></a>
##### IdleSession:delete(`opts`)

Delete a saved session

**Parameters:**
  * **opts**? `(`[`finni.SideEffects.Notify`](<#finni.SideEffects.Notify>)` & `[`finni.SideEffects.SilenceErrors`](<#finni.SideEffects.SilenceErrors>)`)`

    Table fields:

    * **notify**? `boolean`\
      Notify on success
    * **silence_errors**? `boolean`\
      Don't error during this operation

<a id="finni.core.IdleSession:attach()"></a>
##### IdleSession:attach()

Attach this session. If it was loaded from a snapshot file, you must ensure you restore
the snapshot (`:restore()`) before calling this method.
It's fine to attach an already attached session.

**Returns:** [`finni.core.ActiveSession`](<#finni.core.ActiveSession>)

<a id="finni.core.IdleSession:save()"></a>
##### IdleSession:save(`opts`)

Save this session following its configured configuration.
Note: Any save configuration must be applied via `Session.update(opts)` before
callig this method since all session-specific options that might be contained
in `opts` are overridded with ones configured for the session.

**Parameters:**
  * **opts** `unknown`\
    Success notification setting plus options that need to be passed through to pre_save/post_save hooks.


**Returns:** **success** `boolean`

<a id="finni.core.layout.WinInfo"></a>
#### `finni.core.layout.WinInfo` (Class)

Window-specific snapshot data

**Fields:**

* **bufname** `string`\
  The name of the buffer that's displayed in the window.
* **bufuuid** [`finni.core.BufUUID`](<#finni.core.BufUUID>)\
  The buffer's UUID to track it over multiple sessions.
* **current** `boolean`\
  Whether the window was the active one when saved.
* **view** `vim.fn.winsaveview.ret`\
  Cursor position in file, relative position of file in window, curswant and other state
* **width** `integer`\
  Width of the window in number of columns.
* **height** `integer`\
  Height of the window in number of rows.
* **options** `table<string,any>`\
  Window-scoped options.
* **old_winid** [`finni.core.WinID`](<#finni.core.WinID>)\
  Window ID when snapshot was saved. Used to keep track of individual windows, especially loclist window restoration.
* **extension_data** `any`\
  If the window is supported by an extension, the data it needs to remember.
* **cursor**? [`finni.core.AnonymousMark`](<#finni.core.AnonymousMark>)\
  (row, col) tuple of the cursor position, mark-like => (1, 0)-indexed. Deprecated in favor of view.

  Table fields:

  * **[1]** `integer`\
    Line number
  * **[2]** `integer`\
    Column number
* **cwd**? `string`\
  If a local working directory was set for the window, its path.
* **extension**? `string`\
  If the window is supported by an extension, the name of the extension.
* **jumps**? `(`[`finni.core.layout.WinInfo.JumplistEntry`](<#finni.core.layout.WinInfo.JumplistEntry>)`[],integer)`\
  Window-local jumplist, number of steps from last entry to currently active one
* **alt**? `integer`\
  Index of the alternate file for this window in `buflist`, if any
* **loclist_win**? [`finni.core.WinID`](<#finni.core.WinID>)\
  Present for loclist windows. Window ID of the associated window, the one that opens selections (`filewinid`).
* **loclists**? `(`[`finni.core.Snapshot.QFList`](<#finni.core.Snapshot.QFList>)`[],integer)`\
  Location list stack and position of currently active one.

<a id="finni.core.layout.WinInfo.JumplistEntry"></a>
#### `finni.core.layout.WinInfo.JumplistEntry` (Class)

**Fields:**

* **[1]** `integer`\
  Index of absolute path to file this mark references in `buflist`
* **[2]** `integer`\
  Line number
* **[3]** `integer`\
  Column number

<a id="finni.core.layout.WinLayout"></a>
#### `finni.core.layout.WinLayout` (Alias)

**Type:** `(`[`finni.core.layout.WinLayoutLeaf`](<#finni.core.layout.WinLayoutLeaf>)`|`[`finni.core.layout.WinLayoutBranch`](<#finni.core.layout.WinLayoutBranch>)`)`


<a id="finni.core.layout.WinLayoutBranch"></a>
#### `finni.core.layout.WinLayoutBranch` (Class)

**Fields:**

* **[1]** `("row"|"col")`\
  Node type
* **[2]** `(`[`finni.core.layout.WinLayoutLeaf`](<#finni.core.layout.WinLayoutLeaf>)`|`[`finni.core.layout.WinLayoutBranch`](<#finni.core.layout.WinLayoutBranch>)`)[]`\
  children

<a id="finni.core.layout.WinLayoutLeaf"></a>
#### `finni.core.layout.WinLayoutLeaf` (Class)

**Fields:**

* **[1]** `"leaf"`\
  Node type
* **[2]** [`finni.core.layout.WinInfo`](<#finni.core.layout.WinInfo>)\
  Saved window info

  Table fields:

  * **bufname** `string`\
    The name of the buffer that's displayed in the window.
  * **bufuuid** [`finni.core.BufUUID`](<#finni.core.BufUUID>)\
    The buffer's UUID to track it over multiple sessions.
  * **current** `boolean`\
    Whether the window was the active one when saved.
  * **cursor**? [`finni.core.AnonymousMark`](<#finni.core.AnonymousMark>)\
    (row, col) tuple of the cursor position, mark-like => (1, 0)-indexed. Deprecated in favor of view.
  * **view** `vim.fn.winsaveview.ret`\
    Cursor position in file, relative position of file in window, curswant and other state
  * **width** `integer`\
    Width of the window in number of columns.
  * **height** `integer`\
    Height of the window in number of rows.
  * **options** `table<string,any>`\
    Window-scoped options.
  * **old_winid** [`finni.core.WinID`](<#finni.core.WinID>)\
    Window ID when snapshot was saved. Used to keep track of individual windows, especially loclist window restoration.
  * **cwd**? `string`\
    If a local working directory was set for the window, its path.
  * **extension_data** `any`\
    If the window is supported by an extension, the data it needs to remember.
  * **extension**? `string`\
    If the window is supported by an extension, the name of the extension.
  * **jumps**? `(`[`finni.core.layout.WinInfo.JumplistEntry`](<#finni.core.layout.WinInfo.JumplistEntry>)`[],integer)`\
    Window-local jumplist, number of steps from last entry to currently active one
  * **alt**? `integer`\
    Index of the alternate file for this window in `buflist`, if any
  * **loclist_win**? [`finni.core.WinID`](<#finni.core.WinID>)\
    Present for loclist windows. Window ID of the associated window, the one that opens selections (`filewinid`).
  * **loclists**? `(`[`finni.core.Snapshot.QFList`](<#finni.core.Snapshot.QFList>)`[],integer)`\
    Location list stack and position of currently active one.

<a id="finni.core.PassthroughOpts"></a>
#### `finni.core.PassthroughOpts` (Alias)

**Type:** `table`

Indicates that any unhandled opts are also passed through to custom hooks.


<a id="finni.core.PendingSession"></a>
#### `finni.core.PendingSession` (Class)

Represents a session that has been loaded from a snapshot and needs
to be applied still before being able to attach it.

**Fields:**

* **session_file** `string`\
  Path to the session file
* **state_dir** `string`\
  Path to the directory holding session-associated data
* **context_dir** `string`\
  Directory for shared state between all sessions in the same context
  (`dir` for manual sessions, project dir for autosessions)
* **autosave_enabled** `boolean`\
  When this session is attached, automatically save it in intervals. Defaults to false.
* **autosave_interval** `integer`\
  Seconds between autosaves of this session, if enabled. Defaults to 60.
* **name** `string`
* **tab_scoped** `boolean`
* **needs_restore** `true`\
  Indicates this session has been loaded from a snapshot, but not restored yet.
  This session object cannot be attached yet, it needs to be restored first.
* **autosave_notify**? `boolean`\
  Trigger a notification when autosaving this session. Defaults to true.
* **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
  A function that's called when attaching to this session. No global default.
* **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
  A function that's called when detaching from this session. No global default.
* **meta**? `table`\
  External data remembered in association with this session. Useful to build on top of the core API.
* **options**? `string[]`\
  Save and restore these neovim (global/buffer/tab/window) options
* **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **modified**? `(boolean|"auto")`\
  Save/load modified buffers and their undo history.
  If set to `auto` (default), does not save, but still restores modified buffers.
* **jumps**? `boolean`\
  Save/load window-specific jumplists, including current position
  (yes, for **all windows**, not just the active one like with ShaDa).
  If set to `auto` (default), does not save, but still restores saved jumplists.
* **changelist**? `boolean`\
  Save/load buffer-specific changelist (all buffers) and
  changelist position (visible buffers only).

  **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
  Consider tracking `local_marks` in addition to this.
* **global_marks**? `boolean`\
  Save/load global marks (A-Z, not 0-9 currently).

  _Only in global sessions._
* **local_marks**? `boolean`\
  Save/load buffer-specific (local) marks.

  **Note**: Enable this if you track the `changelist`.
* **search_history**? `(integer|boolean)`\
  Maximum number of search history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **command_history**? `(integer|boolean)`\
  Maximum number of command history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **input_history**? `(integer|boolean)`\
  Maximum number of input history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **expr_history**? `boolean`\
  Persist expression history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **debug_history**? `boolean`\
  Persist debug history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **tabid**? [`finni.core.TabID`](<#finni.core.TabID>)

<a id="finni.core.PendingSession.new()"></a>
##### new(`name`, `session_file`, `state_dir`, `context_dir`, `opts`, `tabid`, `needs_restore`)

**Parameters:**
  * **name** `string`

  * **session_file** `string`

  * **state_dir** `string`

  * **context_dir** `string`

  * **opts** [`finni.core.Session.InitOptsWithMeta`](<#finni.core.Session.InitOptsWithMeta>)

  * **tabid** `true`

  * **needs_restore** `true`


**Returns:** [`finni.core.PendingSession`](<#finni.core.PendingSession>)`<`[`finni.core.Session.TabTarget`](<#finni.core.Session.TabTarget>)`>`

<a id="finni.core.PendingSession.from_snapshot()"></a>
##### from_snapshot(`name`, `session_file`, `state_dir`, `context_dir`, `opts`)

Create a new session by loading a snapshot, which you need to restore explicitly.

**Parameters:**
  * **name** `string`

  * **session_file** `string`

  * **state_dir** `string`

  * **context_dir** `string`

  * **opts** `(`[`finni.core.Session.InitOptsWithMeta`](<#finni.core.Session.InitOptsWithMeta>)` & `[`finni.SideEffects.SilenceErrors`](<#finni.SideEffects.SilenceErrors>)`)`

    Table fields:

    * **autosave_enabled**? `boolean`\
      When this session is attached, automatically save it in intervals. Defaults to false.
    * **autosave_interval**? `integer`\
      Seconds between autosaves of this session, if enabled. Defaults to 60.
    * **autosave_notify**? `boolean`\
      Trigger a notification when autosaving this session. Defaults to true.
    * **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
      A function that's called when attaching to this session. No global default.
    * **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
      A function that's called when detaching from this session. No global default.
    * **options**? `string[]`\
      Save and restore these neovim (global/buffer/tab/window) options
    * **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
    * **modified**? `(boolean|"auto")`\
      Save/load modified buffers and their undo history.
      If set to `auto` (default), does not save, but still restores modified buffers.
    * **jumps**? `boolean`\
      Save/load window-specific jumplists, including current position
      (yes, for **all windows**, not just the active one like with ShaDa).
      If set to `auto` (default), does not save, but still restores saved jumplists.
    * **changelist**? `boolean`\
      Save/load buffer-specific changelist (all buffers) and
      changelist position (visible buffers only).

      **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
      Consider tracking `local_marks` in addition to this.
    * **global_marks**? `boolean`\
      Save/load global marks (A-Z, not 0-9 currently).

      _Only in global sessions._
    * **local_marks**? `boolean`\
      Save/load buffer-specific (local) marks.

      **Note**: Enable this if you track the `changelist`.
    * **search_history**? `(integer|boolean)`\
      Maximum number of search history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **command_history**? `(integer|boolean)`\
      Maximum number of command history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **input_history**? `(integer|boolean)`\
      Maximum number of input history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._
    * **expr_history**? `boolean`\
      Persist expression history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **debug_history**? `boolean`\
      Persist debug history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._
    * **meta**? `table`\
      External data remembered in association with this session. Useful to build on top of the core API.
    * **silence_errors**? `boolean`\
      Don't error during this operation

**Returns:**
  * **loaded_session**? [`finni.core.PendingSession`](<#finni.core.PendingSession>)\
    Session object, if the snapshot could be loaded

  * **snapshot**? [`finni.core.Snapshot`](<#finni.core.Snapshot>)\
    Snapshot data, if it could be loaded


<a id="finni.core.PendingSession:add_hook()"></a>
##### PendingSession:add_hook(`event`, `hook`)

**Parameters:**
  * **event** `"detach"`

  * **hook** [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)


**Returns:** `self`

<a id="finni.core.PendingSession:update()"></a>
##### PendingSession:update(`opts`)

Update modifiable options without attaching/detaching a session

**Parameters:**
  * **opts** [`finni.core.Session.InitOptsWithMeta`](<#finni.core.Session.InitOptsWithMeta>)


**Returns:** **modified** `boolean`\
Indicates whether any config modifications occurred


<a id="finni.core.PendingSession:restore()"></a>
##### PendingSession:restore(`opts`, `snapshot`)

Restore a snapshot from disk or memory

**Parameters:**
  * **opts**? `(`[`finni.core.Session.RestoreOpts`](<#finni.core.Session.RestoreOpts>)` & `[`finni.core.PassthroughOpts`](<#finni.core.PassthroughOpts>)`)`

    Table fields:

    * **reset**? `boolean`\
      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.
    * **silence_errors**? `boolean`\
      Don't error during this operation
  * **snapshot**? [`finni.core.Snapshot`](<#finni.core.Snapshot>)\
    Snapshot data to restore. If unspecified, loads from file.

    Table fields:

    * **buffers** [`finni.core.Snapshot.BufData`](<#finni.core.Snapshot.BufData>)`[]`\
      Buffer-specific data like name, buffer options, local marks, changelist
    * **tabs** [`finni.core.Snapshot.TabData`](<#finni.core.Snapshot.TabData>)`[]`\
      Tab-specific and window layout data, including tab cwd and window-specific jumplists
    * **tab_scoped** `boolean`\
      Whether this snapshot was derived from a single tab
    * **global** [`finni.core.Snapshot.GlobalData`](<#finni.core.Snapshot.GlobalData>)\
      Global snapshot data like process CWD, global options and global marks
    * **modified**? `table<`[`finni.core.BufUUID`](<#finni.core.BufUUID>)`,true?>`\
      List of buffers (identified by internal UUID) whose unsaved modifications
      were backed up in the snapshot
    * **buflist** `string[]`\
      List of named buffers that are referenced somewhere in this snapshot.
      Used to reduce repetition of buffer paths in save file, especially lists of named marks
      (jumplist, quickfix and location lists).

**Returns:**
  * **self** [`finni.core.IdleSession`](<#finni.core.IdleSession>)\
    The object itself, but now attachable

  * **success** `boolean`\
    Whether restoration was successful. Only sensible when `silence_errors` is true.


<a id="finni.core.PendingSession:is_attached()"></a>
##### PendingSession:is_attached()

I couldn't make TypeGuard<ActiveSession<T>> work properly with method syntax

**Returns:** `TypeGuard<`[`finni.core.ActiveSession`](<#finni.core.ActiveSession>)`>`

<a id="finni.core.PendingSession:opts()"></a>
##### PendingSession:opts()

Turn the session object into opts for snapshot restore/save operations

**Returns:** `(`[`finni.core.Session.Init.Paths`](<#finni.core.Session.Init.Paths>)` & `[`finni.core.Session.Init.Autosave`](<#finni.core.Session.Init.Autosave>)` & `[`finni.core.Session.Init.Meta`](<#finni.core.Session.Init.Meta>)` & `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`)`

<a id="finni.core.PendingSession:info()"></a>
##### PendingSession:info()

Get information about this session

**Returns:** [`finni.core.ActiveSessionInfo`](<#finni.core.ActiveSessionInfo>)

<a id="finni.core.PendingSession:delete()"></a>
##### PendingSession:delete(`opts`)

Delete a saved session

**Parameters:**
  * **opts**? `(`[`finni.SideEffects.Notify`](<#finni.SideEffects.Notify>)` & `[`finni.SideEffects.SilenceErrors`](<#finni.SideEffects.SilenceErrors>)`)`

    Table fields:

    * **notify**? `boolean`\
      Notify on success
    * **silence_errors**? `boolean`\
      Don't error during this operation

<a id="finni.core.Session.AttachHook"></a>
#### `finni.core.Session.AttachHook` (Alias)

**Type:** `fun(session: `[`finni.core.IdleSession`](<#finni.core.IdleSession>)`)`

Attach hooks can inspect the session.
Modifying it in-place should work, but it's not officially supported.


<a id="finni.core.Session.DetachHook"></a>
#### `finni.core.Session.DetachHook` (Alias)

**Type:** `(fun(session: `[`finni.core.ActiveSession`](<#finni.core.ActiveSession>)`, reason: (`[`finni.core.Session.DetachReasonBuiltin`](<#finni.core.Session.DetachReasonBuiltin>)`|string), opts: (`[`finni.core.Session.DetachOpts`](<#finni.core.Session.DetachOpts>)` & `[`finni.core.PassthroughOpts`](<#finni.core.PassthroughOpts>)`)) -> (`[`finni.core.Session.DetachOpts`](<#finni.core.Session.DetachOpts>)` & `[`finni.core.PassthroughOpts`](<#finni.core.PassthroughOpts>)`))?`

Detach hooks can modify detach opts in place or return new ones.
They can inspect the session. Modifying it in-place should work, but it's not officially supported.


<a id="finni.core.Session.DetachOpts"></a>
#### `finni.core.Session.DetachOpts` (Alias)

**Type:** `(`[`finni.SideEffects.Reset`](<#finni.SideEffects.Reset>)` & `[`finni.SideEffects.Save`](<#finni.SideEffects.Save>)`)`

Options for detaching sessions

**Fields:**

* **reset**? `boolean`\
  When detaching a session in the process, unload associated resources/reset
  everything during the operation when restoring a snapshot.
* **save**? `boolean`\
  Save/override autosave config for affected sessions before the operation


<a id="finni.core.Session.DetachReasonBuiltin"></a>
#### `finni.core.Session.DetachReasonBuiltin` (Alias)

**Type:** `("delete"|"load"|"quit"|"request"|"save"|"tab_closed")`

Detach reasons are passed to avoid unintended side effects during operations. They are passed to
detach hooks as well. These are the ones built in to the core session handling.


<a id="finni.core.Session.Init.Autosave"></a>
#### `finni.core.Session.Init.Autosave` (Class)

**Fields:**

* **autosave_enabled**? `boolean`\
  When this session is attached, automatically save it in intervals. Defaults to false.
* **autosave_interval**? `integer`\
  Seconds between autosaves of this session, if enabled. Defaults to 60.
* **autosave_notify**? `boolean`\
  Trigger a notification when autosaving this session. Defaults to true.

<a id="finni.core.Session.Init.Hooks"></a>
#### `finni.core.Session.Init.Hooks` (Class)

**Fields:**

* **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
  A function that's called when attaching to this session. No global default.
* **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
  A function that's called when detaching from this session. No global default.

<a id="finni.core.Session.Init.Meta"></a>
#### `finni.core.Session.Init.Meta` (Class)

**Fields:**

* **meta**? `table`\
  External data remembered in association with this session. Useful to build on top of the core API.

<a id="finni.core.Session.Init.Paths"></a>
#### `finni.core.Session.Init.Paths` (Class)

**Fields:**

* **session_file** `string`\
  Path to the session file
* **state_dir** `string`\
  Path to the directory holding session-associated data
* **context_dir** `string`\
  Directory for shared state between all sessions in the same context
  (`dir` for manual sessions, project dir for autosessions)

<a id="finni.core.Session.InitOpts"></a>
#### `finni.core.Session.InitOpts` (Alias)

**Type:** `(`[`finni.core.Session.Init.Autosave`](<#finni.core.Session.Init.Autosave>)` & `[`finni.core.Session.Init.Hooks`](<#finni.core.Session.Init.Hooks>)` & `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`)`

Options to influence how an attached session is handled.

**Fields:**

* **autosave_enabled**? `boolean`\
  When this session is attached, automatically save it in intervals. Defaults to false.
* **autosave_interval**? `integer`\
  Seconds between autosaves of this session, if enabled. Defaults to 60.
* **autosave_notify**? `boolean`\
  Trigger a notification when autosaving this session. Defaults to true.
* **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
  A function that's called when attaching to this session. No global default.
* **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
  A function that's called when detaching from this session. No global default.
* **options**? `string[]`\
  Save and restore these neovim (global/buffer/tab/window) options
* **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **modified**? `(boolean|"auto")`\
  Save/load modified buffers and their undo history.
  If set to `auto` (default), does not save, but still restores modified buffers.
* **jumps**? `boolean`\
  Save/load window-specific jumplists, including current position
  (yes, for **all windows**, not just the active one like with ShaDa).
  If set to `auto` (default), does not save, but still restores saved jumplists.
* **changelist**? `boolean`\
  Save/load buffer-specific changelist (all buffers) and
  changelist position (visible buffers only).

  **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
  Consider tracking `local_marks` in addition to this.
* **global_marks**? `boolean`\
  Save/load global marks (A-Z, not 0-9 currently).

  _Only in global sessions._
* **local_marks**? `boolean`\
  Save/load buffer-specific (local) marks.

  **Note**: Enable this if you track the `changelist`.
* **search_history**? `(integer|boolean)`\
  Maximum number of search history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **command_history**? `(integer|boolean)`\
  Maximum number of command history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **input_history**? `(integer|boolean)`\
  Maximum number of input history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **expr_history**? `boolean`\
  Persist expression history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **debug_history**? `boolean`\
  Persist debug history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._


<a id="finni.core.Session.InitOptsWithMeta"></a>
#### `finni.core.Session.InitOptsWithMeta` (Alias)

**Type:** `(`[`finni.core.Session.InitOpts`](<#finni.core.Session.InitOpts>)` & `[`finni.core.Session.Init.Meta`](<#finni.core.Session.Init.Meta>)`)`

Options to influence how an attached session is handled plus `meta` field, which can only be populated by passing
it to the session constructor and is useful for custom session handling.

**Fields:**

* **autosave_enabled**? `boolean`\
  When this session is attached, automatically save it in intervals. Defaults to false.
* **autosave_interval**? `integer`\
  Seconds between autosaves of this session, if enabled. Defaults to 60.
* **autosave_notify**? `boolean`\
  Trigger a notification when autosaving this session. Defaults to true.
* **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
  A function that's called when attaching to this session. No global default.
* **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
  A function that's called when detaching from this session. No global default.
* **options**? `string[]`\
  Save and restore these neovim (global/buffer/tab/window) options
* **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **modified**? `(boolean|"auto")`\
  Save/load modified buffers and their undo history.
  If set to `auto` (default), does not save, but still restores modified buffers.
* **jumps**? `boolean`\
  Save/load window-specific jumplists, including current position
  (yes, for **all windows**, not just the active one like with ShaDa).
  If set to `auto` (default), does not save, but still restores saved jumplists.
* **changelist**? `boolean`\
  Save/load buffer-specific changelist (all buffers) and
  changelist position (visible buffers only).

  **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
  Consider tracking `local_marks` in addition to this.
* **global_marks**? `boolean`\
  Save/load global marks (A-Z, not 0-9 currently).

  _Only in global sessions._
* **local_marks**? `boolean`\
  Save/load buffer-specific (local) marks.

  **Note**: Enable this if you track the `changelist`.
* **search_history**? `(integer|boolean)`\
  Maximum number of search history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **command_history**? `(integer|boolean)`\
  Maximum number of command history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **input_history**? `(integer|boolean)`\
  Maximum number of input history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **expr_history**? `boolean`\
  Persist expression history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **debug_history**? `boolean`\
  Persist debug history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **meta**? `table`\
  External data remembered in association with this session. Useful to build on top of the core API.


<a id="finni.core.Session.RestoreOpts"></a>
#### `finni.core.Session.RestoreOpts` (Alias)

**Type:** `(`[`finni.SideEffects.Reset`](<#finni.SideEffects.Reset>)` & `[`finni.SideEffects.SilenceErrors`](<#finni.SideEffects.SilenceErrors>)`)`

Options for basic snapshot restoration (different from session loading!).
Note that `reset` here does not handle detaching other active sessions,
it really resets everything if set to true. If set to false, opens a new tab.
Handle with care!

**Fields:**

* **reset**? `boolean`\
  When detaching a session in the process, unload associated resources/reset
  everything during the operation when restoring a snapshot.
* **silence_errors**? `boolean`\
  Don't error during this operation


<a id="finni.core.Session.TabTarget"></a>
#### `finni.core.Session.TabTarget` (Class)

The associated session is tab-scoped to this specific tab

**Fields:**

* **tab_scoped** `true`
* **tabid** [`finni.core.TabID`](<#finni.core.TabID>)

<a id="finni.core.Snapshot"></a>
#### `finni.core.Snapshot` (Class)

A snapshot of nvim's state.

**Fields:**

* **buffers** [`finni.core.Snapshot.BufData`](<#finni.core.Snapshot.BufData>)`[]`\
  Buffer-specific data like name, buffer options, local marks, changelist

  Table fields:

  * **name** `string`\
    Name of the buffer, usually its path.
    Can be empty when unsaved modifications are backed up.
  * **loaded** `boolean`\
    Whether the buffer was loaded.
  * **options** `table<string,any>`\
    Buffer-specific nvim options.
  * **last_pos** [`finni.core.AnonymousMark`](<#finni.core.AnonymousMark>)\
    Position of the cursor when this buffer was last shown in a window (`"` mark).
    Only updated once a buffer becomes invisible.
    Visible buffer cursors are backed up in the window layout data.
  * **uuid** `string`\
    A buffer-specific UUID intended to track it between sessions. Required to save/restore unnamed buffers.
  * **in_win** `boolean`\
    Whether the buffer is visible in at least one window.
  * **changelist**? `(`[`finni.core.Snapshot.BufData.ChangelistItem`](<#finni.core.Snapshot.BufData.ChangelistItem>)`[],integer)`\
    Changelist and changelist position (backwards from most recent entry) for this buffer.
    Position is always `0` when invisible buffers are saved.
  * **marks**? `table<string,`[`finni.core.AnonymousMark`](<#finni.core.AnonymousMark>)`?>`\
    Saved buffer-local marks, if enabled
  * **bt**? `("acwrite"|"help"|"nofile"|"nowrite"|"quickfix"|"terminal"...)`\
    `buftype` option of buffer. Unset if empty (`""`).
* **tabs** [`finni.core.Snapshot.TabData`](<#finni.core.Snapshot.TabData>)`[]`\
  Tab-specific and window layout data, including tab cwd and window-specific jumplists

  Table fields:

  * **options** `table<string,any>`\
    Tab-specific nvim options. Currently only `cmdheight`.
  * **wins** [`finni.core.layout.WinLayout`](<#finni.core.layout.WinLayout>)\
    Window layout enriched with window-specific snapshot data
  * **cwd**? `string`\
    Tab-local cwd, if different from the global one or a tab-scoped snapshot
  * **current**? `boolean`
* **tab_scoped** `boolean`\
  Whether this snapshot was derived from a single tab
* **global** [`finni.core.Snapshot.GlobalData`](<#finni.core.Snapshot.GlobalData>)\
  Global snapshot data like process CWD, global options and global marks

  Table fields:

  * **cwd** `string`\
    Nvim's global cwd.
  * **height** `integer`\
    `vim.o.lines` - `vim.o.cmdheight`
  * **width** `integer`\
    `vim.o.columns`
  * **options** `table<string,any>`\
    Global nvim options
  * **marks**? `table<string,`[`finni.core.FileMark`](<#finni.core.FileMark>)`?>`\
    Saved global marks, if enabled
  * **search_history** `boolean`\
    Whether search history was saved in session-associated ShaDa file.
    If enabled, corresponding history in nvim process should be cleared before loading.
  * **command_history** `boolean`\
    Whether command history was saved in session-associated ShaDa file.
    If enabled, corresponding history in nvim process should be cleared before loading.
  * **input_history** `boolean`\
    Whether input history was saved in session-associated ShaDa file.
    If enabled, corresponding history in nvim process should be cleared before loading.
  * **expr_history** `boolean`\
    Whether expression history was saved in session-associated ShaDa file.
    If enabled, corresponding history in nvim process should be cleared before loading.
  * **debug_history** `boolean`\
    Whether debug history was saved in session-associated ShaDa file.
    If enabled, corresponding history in nvim process should be cleared before loading.
* **buflist** `string[]`\
  List of named buffers that are referenced somewhere in this snapshot.
  Used to reduce repetition of buffer paths in save file, especially lists of named marks
  (jumplist, quickfix and location lists).
* **modified**? `table<`[`finni.core.BufUUID`](<#finni.core.BufUUID>)`,true?>`\
  List of buffers (identified by internal UUID) whose unsaved modifications
  were backed up in the snapshot

<a id="finni.core.Snapshot.BufData"></a>
#### `finni.core.Snapshot.BufData` (Class)

Buffer-specific snapshot data like path, loaded state, options and last cursor position.

**Fields:**

* **name** `string`\
  Name of the buffer, usually its path.
  Can be empty when unsaved modifications are backed up.
* **loaded** `boolean`\
  Whether the buffer was loaded.
* **options** `table<string,any>`\
  Buffer-specific nvim options.
* **last_pos** [`finni.core.AnonymousMark`](<#finni.core.AnonymousMark>)\
  Position of the cursor when this buffer was last shown in a window (`"` mark).
  Only updated once a buffer becomes invisible.
  Visible buffer cursors are backed up in the window layout data.

  Table fields:

  * **[1]** `integer`\
    Line number
  * **[2]** `integer`\
    Column number
* **uuid** `string`\
  A buffer-specific UUID intended to track it between sessions. Required to save/restore unnamed buffers.
* **in_win** `boolean`\
  Whether the buffer is visible in at least one window.
* **changelist**? `(`[`finni.core.Snapshot.BufData.ChangelistItem`](<#finni.core.Snapshot.BufData.ChangelistItem>)`[],integer)`\
  Changelist and changelist position (backwards from most recent entry) for this buffer.
  Position is always `0` when invisible buffers are saved.
* **marks**? `table<string,`[`finni.core.AnonymousMark`](<#finni.core.AnonymousMark>)`?>`\
  Saved buffer-local marks, if enabled
* **bt**? `("acwrite"|"help"|"nofile"|"nowrite"|"quickfix"|"terminal"...)`\
  `buftype` option of buffer. Unset if empty (`""`).

<a id="finni.core.Snapshot.BufData.ChangelistItem"></a>
#### `finni.core.Snapshot.BufData.ChangelistItem` (Class)

**Fields:**

* **[1]** `integer`\
  Line number
* **[2]** `integer`\
  Column number

<a id="finni.core.snapshot.CreateOpts"></a>
#### `finni.core.snapshot.CreateOpts` (Class)

Options to influence which data is included in a snapshot.

**Fields:**

* **options**? `string[]`\
  Save and restore these neovim (global/buffer/tab/window) options
* **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **modified**? `(boolean|"auto")`\
  Save/load modified buffers and their undo history.
  If set to `auto` (default), does not save, but still restores modified buffers.
* **jumps**? `boolean`\
  Save/load window-specific jumplists, including current position
  (yes, for **all windows**, not just the active one like with ShaDa).
  If set to `auto` (default), does not save, but still restores saved jumplists.
* **changelist**? `boolean`\
  Save/load buffer-specific changelist (all buffers) and
  changelist position (visible buffers only).

  **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
  Consider tracking `local_marks` in addition to this.
* **global_marks**? `boolean`\
  Save/load global marks (A-Z, not 0-9 currently).

  _Only in global sessions._
* **local_marks**? `boolean`\
  Save/load buffer-specific (local) marks.

  **Note**: Enable this if you track the `changelist`.
* **search_history**? `(integer|boolean)`\
  Maximum number of search history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **command_history**? `(integer|boolean)`\
  Maximum number of command history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **input_history**? `(integer|boolean)`\
  Maximum number of input history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **expr_history**? `boolean`\
  Persist expression history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **debug_history**? `boolean`\
  Persist debug history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._

<a id="finni.core.Snapshot.GlobalData"></a>
#### `finni.core.Snapshot.GlobalData` (Class)

Global snapshot data like cwd, height/width and global options.

**Fields:**

* **cwd** `string`\
  Nvim's global cwd.
* **height** `integer`\
  `vim.o.lines` - `vim.o.cmdheight`
* **width** `integer`\
  `vim.o.columns`
* **options** `table<string,any>`\
  Global nvim options
* **search_history** `boolean`\
  Whether search history was saved in session-associated ShaDa file.
  If enabled, corresponding history in nvim process should be cleared before loading.
* **command_history** `boolean`\
  Whether command history was saved in session-associated ShaDa file.
  If enabled, corresponding history in nvim process should be cleared before loading.
* **input_history** `boolean`\
  Whether input history was saved in session-associated ShaDa file.
  If enabled, corresponding history in nvim process should be cleared before loading.
* **expr_history** `boolean`\
  Whether expression history was saved in session-associated ShaDa file.
  If enabled, corresponding history in nvim process should be cleared before loading.
* **debug_history** `boolean`\
  Whether debug history was saved in session-associated ShaDa file.
  If enabled, corresponding history in nvim process should be cleared before loading.
* **marks**? `table<string,`[`finni.core.FileMark`](<#finni.core.FileMark>)`?>`\
  Saved global marks, if enabled

<a id="finni.core.Snapshot.QFList"></a>
#### `finni.core.Snapshot.QFList` (Class)

Represents a quickfix/location list

**Fields:**

* **idx** `integer`\
  Current position in list
* **title** `string`\
  Title of list
* **context** `any`\
  Arbitrary context for this list, may be used by plugins
* **quickfixtextfunc** `string`\
  Function to customize the displayed text
* **items** [`finni.core.Snapshot.QFListItem`](<#finni.core.Snapshot.QFListItem>)`[]`\
  Items in the list

  Table fields:

  * **filename**? `integer`\
    Index of path of the file this entry points to in `buflist`
  * **module** `string`\
    Module name (?)
  * **lnum** `integer`\
    Referenced line in the file, 1-indexed
  * **end_lnum**? `integer`\
    For multiline items, last referenced line
  * **col** `integer`\
    Referenced column in the line of the file, also 1-indexed
  * **end_col**? `integer`\
    For ranged items, last referenced column number
  * **vcol** `boolean`\
    Whether `col` is visual index or byte index
  * **nr** `integer`\
    Item index in the list
  * **pattern** `string`\
    Search pattern used to locate the item
  * **text** `string`\
    Item description
  * **type** `string`\
    Type of the item (?)
  * **valid** `boolean`\
    Whether error message was recognized (?)
* **efm**? `string`\
  Error format string to use for parsing lines

<a id="finni.core.Snapshot.TabData"></a>
#### `finni.core.Snapshot.TabData` (Class)

Tab-specific (options, cwd) and window layout snapshot data.

**Fields:**

* **options** `table<string,any>`\
  Tab-specific nvim options. Currently only `cmdheight`.
* **wins** [`finni.core.layout.WinLayout`](<#finni.core.layout.WinLayout>)\
  Window layout enriched with window-specific snapshot data
* **cwd**? `string`\
  Tab-local cwd, if different from the global one or a tab-scoped snapshot
* **current**? `boolean`

<a id="finni.core.TabID"></a>
#### `finni.core.TabID` (Alias)

**Type:** `integer`

Nvim tab ID


<a id="finni.core.WinID"></a>
#### `finni.core.WinID` (Alias)

**Type:** `integer`

Nvim window ID


<a id="finni.log.Level"></a>
#### `finni.log.Level` (Alias)

**Type:** `("TRACE"|"DEBUG"|"INFO"|"WARN"|"ERROR"|"OFF")`

Log level name in uppercase, for internal references and log output


<a id="finni.log.Line"></a>
#### `finni.log.Line` (Class)

Log call information passed to `handler`

**Fields:**

* **level** [`finni.log.Level`](<#finni.log.Level>)\
  Name of log level, uppercase
* **message** `string`\
  Final, formatted log message
* **timestamp** `integer`\
  UNIX timestamp of log message
* **hrtime** `number`\
  High-resolution time of log message (`[ns]`, arbitrary anchor)
* **src_path** `string`\
  Absolute path to the file the log call originated from
* **src_line** `integer`\
  Line in `src_path` the log call originated from

<a id="finni.session.DeleteOpts"></a>
#### `finni.session.DeleteOpts` (Alias)

**Type:** `(`[`finni.session.DirParam`](<#finni.session.DirParam>)` & `[`finni.SideEffects.Notify`](<#finni.SideEffects.Notify>)` & `[`finni.SideEffects.Reset`](<#finni.SideEffects.Reset>)` & `[`finni.SideEffects.SilenceErrors`](<#finni.SideEffects.SilenceErrors>)`)`

API options for `session.delete`

**Fields:**

* **dir**? `string`\
  Name of session directory (overrides config.dir)
* **notify**? `boolean`\
  Notify on success
* **reset**? `boolean`\
  When detaching a session in the process, unload associated resources/reset
  everything during the operation when restoring a snapshot.
* **silence_errors**? `boolean`\
  Don't error during this operation


<a id="finni.session.DirParam"></a>
#### `finni.session.DirParam` (Class)

**Fields:**

* **dir**? `string`\
  Name of session directory (overrides config.dir)

<a id="finni.session.LoadOpts"></a>
#### `finni.session.LoadOpts` (Alias)

**Type:** `(`[`finni.session.DirParam`](<#finni.session.DirParam>)` & `[`finni.core.Session.InitOptsWithMeta`](<#finni.core.Session.InitOptsWithMeta>)` & `[`finni.SideEffects.Attach`](<#finni.SideEffects.Attach>)` & `[`finni.SideEffects.ResetAuto`](<#finni.SideEffects.ResetAuto>)` & `[`finni.SideEffects.Save`](<#finni.SideEffects.Save>)` & `[`finni.SideEffects.SilenceErrors`](<#finni.SideEffects.SilenceErrors>)`)`

API options for `session.load`

**Fields:**

* **dir**? `string`\
  Name of session directory (overrides config.dir)
* **autosave_enabled**? `boolean`\
  When this session is attached, automatically save it in intervals. Defaults to false.
* **autosave_interval**? `integer`\
  Seconds between autosaves of this session, if enabled. Defaults to 60.
* **autosave_notify**? `boolean`\
  Trigger a notification when autosaving this session. Defaults to true.
* **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
  A function that's called when attaching to this session. No global default.
* **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
  A function that's called when detaching from this session. No global default.
* **options**? `string[]`\
  Save and restore these neovim (global/buffer/tab/window) options
* **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **modified**? `(boolean|"auto")`\
  Save/load modified buffers and their undo history.
  If set to `auto` (default), does not save, but still restores modified buffers.
* **jumps**? `boolean`\
  Save/load window-specific jumplists, including current position
  (yes, for **all windows**, not just the active one like with ShaDa).
  If set to `auto` (default), does not save, but still restores saved jumplists.
* **changelist**? `boolean`\
  Save/load buffer-specific changelist (all buffers) and
  changelist position (visible buffers only).

  **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
  Consider tracking `local_marks` in addition to this.
* **global_marks**? `boolean`\
  Save/load global marks (A-Z, not 0-9 currently).

  _Only in global sessions._
* **local_marks**? `boolean`\
  Save/load buffer-specific (local) marks.

  **Note**: Enable this if you track the `changelist`.
* **search_history**? `(integer|boolean)`\
  Maximum number of search history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **command_history**? `(integer|boolean)`\
  Maximum number of command history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **input_history**? `(integer|boolean)`\
  Maximum number of input history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **expr_history**? `boolean`\
  Persist expression history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **debug_history**? `boolean`\
  Persist debug history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **meta**? `table`\
  External data remembered in association with this session. Useful to build on top of the core API.
* **attach**? `boolean`\
  Attach to/stay attached to session after operation
* **reset**? `(boolean|"auto")`\
  When detaching a session in the process, unload associated resources/reset
  everything during the operation when restoring a snapshot.
  `auto` resets only for global sessions.
* **save**? `boolean`\
  Save/override autosave config for affected sessions before the operation
* **silence_errors**? `boolean`\
  Don't error during this operation


<a id="finni.session.SaveOpts"></a>
#### `finni.session.SaveOpts` (Alias)

**Type:** `(`[`finni.session.DirParam`](<#finni.session.DirParam>)` & `[`finni.core.Session.InitOptsWithMeta`](<#finni.core.Session.InitOptsWithMeta>)` & `[`finni.SideEffects.Attach`](<#finni.SideEffects.Attach>)` & `[`finni.SideEffects.Notify`](<#finni.SideEffects.Notify>)` & `[`finni.SideEffects.Reset`](<#finni.SideEffects.Reset>)`)`

API options for `session.save`

**Fields:**

* **dir**? `string`\
  Name of session directory (overrides config.dir)
* **autosave_enabled**? `boolean`\
  When this session is attached, automatically save it in intervals. Defaults to false.
* **autosave_interval**? `integer`\
  Seconds between autosaves of this session, if enabled. Defaults to 60.
* **autosave_notify**? `boolean`\
  Trigger a notification when autosaving this session. Defaults to true.
* **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
  A function that's called when attaching to this session. No global default.
* **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
  A function that's called when detaching from this session. No global default.
* **options**? `string[]`\
  Save and restore these neovim (global/buffer/tab/window) options
* **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **modified**? `(boolean|"auto")`\
  Save/load modified buffers and their undo history.
  If set to `auto` (default), does not save, but still restores modified buffers.
* **jumps**? `boolean`\
  Save/load window-specific jumplists, including current position
  (yes, for **all windows**, not just the active one like with ShaDa).
  If set to `auto` (default), does not save, but still restores saved jumplists.
* **changelist**? `boolean`\
  Save/load buffer-specific changelist (all buffers) and
  changelist position (visible buffers only).

  **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
  Consider tracking `local_marks` in addition to this.
* **global_marks**? `boolean`\
  Save/load global marks (A-Z, not 0-9 currently).

  _Only in global sessions._
* **local_marks**? `boolean`\
  Save/load buffer-specific (local) marks.

  **Note**: Enable this if you track the `changelist`.
* **search_history**? `(integer|boolean)`\
  Maximum number of search history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **command_history**? `(integer|boolean)`\
  Maximum number of command history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **input_history**? `(integer|boolean)`\
  Maximum number of input history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **expr_history**? `boolean`\
  Persist expression history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **debug_history**? `boolean`\
  Persist debug history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **meta**? `table`\
  External data remembered in association with this session. Useful to build on top of the core API.
* **attach**? `boolean`\
  Attach to/stay attached to session after operation
* **notify**? `boolean`\
  Notify on success
* **reset**? `boolean`\
  When detaching a session in the process, unload associated resources/reset
  everything during the operation when restoring a snapshot.


<a id="finni.SideEffects.Attach"></a>
#### `finni.SideEffects.Attach` (Class)

**Fields:**

* **attach**? `boolean`\
  Attach to/stay attached to session after operation

<a id="finni.SideEffects.Notify"></a>
#### `finni.SideEffects.Notify` (Class)

**Fields:**

* **notify**? `boolean`\
  Notify on success

<a id="finni.SideEffects.Reset"></a>
#### `finni.SideEffects.Reset` (Class)

**Fields:**

* **reset**? `boolean`\
  When detaching a session in the process, unload associated resources/reset
  everything during the operation when restoring a snapshot.

<a id="finni.SideEffects.ResetAuto"></a>
#### `finni.SideEffects.ResetAuto` (Class)

**Fields:**

* **reset**? `(boolean|"auto")`\
  When detaching a session in the process, unload associated resources/reset
  everything during the operation when restoring a snapshot.
  `auto` resets only for global sessions.

<a id="finni.SideEffects.Save"></a>
#### `finni.SideEffects.Save` (Class)

**Fields:**

* **save**? `boolean`\
  Save/override autosave config for affected sessions before the operation

<a id="finni.SideEffects.SilenceErrors"></a>
#### `finni.SideEffects.SilenceErrors` (Class)

**Fields:**

* **silence_errors**? `boolean`\
  Don't error during this operation

<a id="finni.UserConfig.autosession"></a>
#### `finni.UserConfig.autosession` (Class)

Configure autosession behavior and contents

**Fields:**

* **config**? [`finni.core.Session.InitOpts`](<#finni.core.Session.InitOpts>)\
  Save/load configuration for autosessions

  Table fields:

  * **autosave_enabled**? `boolean`\
    When this session is attached, automatically save it in intervals. Defaults to false.
  * **autosave_interval**? `integer`\
    Seconds between autosaves of this session, if enabled. Defaults to 60.
  * **autosave_notify**? `boolean`\
    Trigger a notification when autosaving this session. Defaults to true.
  * **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
    A function that's called when attaching to this session. No global default.
  * **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
    A function that's called when detaching from this session. No global default.
  * **options**? `string[]`\
    Save and restore these neovim (global/buffer/tab/window) options
  * **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
  * **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
  * **modified**? `(boolean|"auto")`\
    Save/load modified buffers and their undo history.
    If set to `auto` (default), does not save, but still restores modified buffers.
  * **jumps**? `boolean`\
    Save/load window-specific jumplists, including current position
    (yes, for **all windows**, not just the active one like with ShaDa).
    If set to `auto` (default), does not save, but still restores saved jumplists.
  * **changelist**? `boolean`\
    Save/load buffer-specific changelist (all buffers) and
    changelist position (visible buffers only).

    **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
    Consider tracking `local_marks` in addition to this.
  * **global_marks**? `boolean`\
    Save/load global marks (A-Z, not 0-9 currently).

    _Only in global sessions._
  * **local_marks**? `boolean`\
    Save/load buffer-specific (local) marks.

    **Note**: Enable this if you track the `changelist`.
  * **search_history**? `(integer|boolean)`\
    Maximum number of search history items to persist. Defaults to false.
    If set to `true`, maps to the `'history'` option.

    _Only in global sessions._
  * **command_history**? `(integer|boolean)`\
    Maximum number of command history items to persist. Defaults to false.
    If set to `true`, maps to the `'history'` option.

    _Only in global sessions._
  * **input_history**? `(integer|boolean)`\
    Maximum number of input history items to persist. Defaults to false.
    If set to `true`, maps to the `'history'` option.

    _Only in global sessions._
  * **expr_history**? `boolean`\
    Persist expression history. Defaults to false.
    **Note**: Cannot set limit (currently), no direct support by neovim.

    _Only in global sessions._
  * **debug_history**? `boolean`\
    Persist debug history. Defaults to false.
    **Note**: Cannot set limit (currently), no direct support by neovim.

    _Only in global sessions._
* **dir**? `string`\
  Name of the directory to store autosession projects in.
  Interpreted relative to `$XDG_STATE_HOME/$NVIM_APPNAME`.
* **spec**? `fun(cwd: string) -> `[`finni.auto.AutosessionSpec`](<#finni.auto.AutosessionSpec>)`?`
* **workspace**? `fun(cwd: string) -> (string,boolean)`
* **project_name**? `fun(workspace: string, git_info: `[`finni.auto.AutosessionSpec.GitInfo`](<#finni.auto.AutosessionSpec.GitInfo>)`?) -> string`
* **session_name**? `fun(meta: {...}) -> string`
* **enabled**? `fun(meta: {...}) -> boolean`
* **load_opts**? `fun(meta: {...}) -> `[`finni.auto.LoadOpts`](<#finni.auto.LoadOpts>)`?`

<a id="finni.UserConfig.load"></a>
#### `finni.UserConfig.load` (Class)

Configure session list information detail and sort order

**Fields:**

* **detail**? `boolean`\
  Show more detail about the sessions when selecting one to load.
  Disable if it causes lag.
* **order**? `("modification_time"|"creation_time"|"filename")`\
  Session list order

<a id="finni.UserConfig.log"></a>
#### `finni.UserConfig.log` (Class)

Configure plugin logging

**Fields:**

* **level**? `("trace"|"debug"|"info"|"warn"|"error"|"off")`\
  Minimum level to log at. Defaults to `warn`.
* **notify_level**? `("trace"|"debug"|"info"|"warn"|"error"|"off")`\
  Minimum level to use `vim.notify` for. Defaults to `warn`.
* **notify_opts**? `table`\
  Options to pass to `vim.notify`. Defaults to `{ title = "Finni" }`
* **format**? `string`\
  Log line format string. Note that this works like Python's f-strings.
  Defaults to `[%(level)s %(dtime)s] %(message)s%(src_sep)s[%(src_path)s:%(src_line)s]`.
  Available parameters:
  * `level` Uppercase level name
  * `message` Log message
  * `dtime` Formatted date/time string
  * `hrtime` Time in `[ns]` without absolute anchor
  * `src_path` Path to the file that called the log function
  * `src_line` Line in `src_path` that called the log function
  * `src_sep` Whitespace between log line and source of call, 2 tabs for single line, newline + tab for multiline log messages
* **notify_format**? `string`\
  Same as `format`, but for `vim.notify` message display. Defaults to `%(message)s`.
* **time_format**? `string`\
  `strftime` format string used for rendering time of call. Defaults to `%Y-%m-%d %H:%M:%S`
* **handler**? `fun(line: `[`finni.log.Line`](<#finni.log.Line>)`)`

<a id="finni.UserConfig.session"></a>
#### `finni.UserConfig.session` (Class)

Configure default session behavior and contents, affects both manual and autosessions.

**Fields:**

* **autosave_enabled**? `boolean`\
  When this session is attached, automatically save it in intervals. Defaults to false.
* **autosave_interval**? `integer`\
  Seconds between autosaves of this session, if enabled. Defaults to 60.
* **autosave_notify**? `boolean`\
  Trigger a notification when autosaving this session. Defaults to true.
* **on_attach**? [`finni.core.Session.AttachHook`](<#finni.core.Session.AttachHook>)\
  A function that's called when attaching to this session. No global default.
* **on_detach**? [`finni.core.Session.DetachHook`](<#finni.core.Session.DetachHook>)\
  A function that's called when detaching from this session. No global default.
* **options**? `string[]`\
  Save and restore these neovim (global/buffer/tab/window) options
* **buf_filter**? `fun(bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: `[`finni.core.snapshot.CreateOpts`](<#finni.core.snapshot.CreateOpts>)`) -> boolean`
* **modified**? `(boolean|"auto")`\
  Save/load modified buffers and their undo history.
  If set to `auto` (default), does not save, but still restores modified buffers.
* **jumps**? `boolean`\
  Save/load window-specific jumplists, including current position
  (yes, for **all windows**, not just the active one like with ShaDa).
  If set to `auto` (default), does not save, but still restores saved jumplists.
* **changelist**? `boolean`\
  Save/load buffer-specific changelist (all buffers) and
  changelist position (visible buffers only).

  **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
  Consider tracking `local_marks` in addition to this.
* **global_marks**? `boolean`\
  Save/load global marks (A-Z, not 0-9 currently).

  _Only in global sessions._
* **local_marks**? `boolean`\
  Save/load buffer-specific (local) marks.

  **Note**: Enable this if you track the `changelist`.
* **search_history**? `(integer|boolean)`\
  Maximum number of search history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **command_history**? `(integer|boolean)`\
  Maximum number of command history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **input_history**? `(integer|boolean)`\
  Maximum number of input history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._
* **expr_history**? `boolean`\
  Persist expression history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **debug_history**? `boolean`\
  Persist debug history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._
* **dir**? `string`\
  Name of the directory to store regular sessions in.
  Interpreted relative to `$XDG_STATE_HOME/$NVIM_APPNAME`.



<a id="finni-extensions"></a>
## Extensions

<a id="finni-extensions-built-in"></a>
### Built-in
* **quickfix**:

  Persist all quickfix lists, currently active list, active position in list and quickfix window.

* **colorscheme**:

  Persist color scheme.

* [**neogit**](https://github.com/NeogitOrg/neogit):

  Persist Neogit status and commit views.

* [**oil.nvim**](https://github.com/stevearc/oil.nvim):

  Persist Oil windows.

  Note: Customized from the one embedded in `oil.nvim` to correctly restore view.

<a id="finni-extensions-external"></a>
### External
Here are some examples of external extensions:

* [**aerial.nvim**](https://github.com/stevearc/aerial.nvim):

  Note: For Resession, which is compatible with Finni.

* [**overseer.nvim**](https://github.com/stevearc/overseer.nvim):

  Note: For Resession, which is compatible with Finni.

<a id="finni-faq"></a>
## FAQ
**Q: Why another session plugin?**

A1: All the other plugins (with the exception of `resession.nvim`)
    use `:mksession` under the hood
A2: Resession cannot be bent enough via its interface to support everything
    Finni does. Its API is difficult to build another plugin on top of
    (e.g. cannot get session table without Resession saving it to a file
    first).

**Q: Why don't you want to use `:mksession`?**

A: While it's amazing that this feature is built-in to vim, and it does an
   impressively good job for most situations, it is very difficult to
   customize. If `:help sessionoptions` covers your use case, then you're
   golden. If you want anything else, you're out of luck.

**Q: Why `Finni`?**

A: One might assume the name of this plugin is a word play on the French
   "c'est fini" or a contraction of "fin" (French: end) and either "nie"
   (German: never) or even the "Ni!" by the "Knights Who Say 'Ni!'",
   for some reason.

   But one would be mistaken.

   This plugin is dedicated to one of the loveliest creatures that ever
   walked our Earth, my little kind-hearted and trustful to a fault
   sweetie Finni. ❤️

   You lived a long life (for a hamster...) and were the best boy
   until the end. I will miss you, your curiosity and your unwavering
   will dearly, my little Finni.

   Like your namesake plugin allows Neovim sessions to, may your memory
   live on forever.
