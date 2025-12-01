# continuity.nvim

```
▄█████  ▄▄▄  ▄▄  ▄▄ ▄▄▄▄▄▄ ▄▄ ▄▄  ▄▄ ▄▄ ▄▄ ▄▄ ▄▄▄▄▄▄ ▄▄ ▄▄
██     ██▀██ ███▄██   ██   ██ ███▄██ ██ ██ ██   ██   ▀███▀
▀█████ ▀███▀ ██ ▀██   ██   ██ ██ ▀██ ▀███▀ ██   ██     █
```

Sublime autosessions.

A flexible, project-focused autosession plugin for Neovim,
unbound by the limits of `:mksession`.

## Table of Contents

1. [Features](<#continuity-features>)
2. [Dependencies](<#continuity-dependencies>)
3. [Setup](<#continuity-setup>)
    * [Built-in plugin manager](<#continuity-setup-nvim-pack>)
    * [lazy.nvim](<#continuity-setup-lazy-nvim>)
4. [Configuration](<#continuity-configuration>)
    * [Defaults](<#continuity-configuration-defaults>)
    * [`continuity.UserConfig` (Class)](<#continuity.UserConfig>)
    * [`continuity.UserConfig.autosession` (Class)](<#continuity.UserConfig.autosession>)
    * [`continuity.UserConfig.load` (Class)](<#continuity.UserConfig.load>)
    * [`continuity.UserConfig.log` (Class)](<#continuity.UserConfig.log>)
    * [`continuity.UserConfig.session` (Class)](<#continuity.UserConfig.session>)
5. [Recipes](<#continuity-recipes>)
    * [Tab-scoped Sessions](<#continuity-recipes-tab-scoped-sessions>)
    * [Custom Extension](<#continuity-recipes-custom-extension>)
6. [API](<#continuity-api>)
    * [Manual Sessions](<#continuity-api-manual-sessions>)
    * [Autosessions](<#continuity-api-autosessions>)
    * [Relevant Types](<#continuity-api-relevant-types>)
7. [Extensions](<#continuity-extensions>)
    * [Built-in](<#continuity-extensions-built-in>)
    * [External](<#continuity-extensions-external>)
8. [FAQ](<#continuity-faq>)

<a id="continuity-features"></a>
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
  (Continuity started by forking it, a heartfelt thank you @stevearc! <3).
- **Tab-scoped** sessions are possible (currently via the manual session API only).

<a id="continuity-dependencies"></a>
## Dependencies
* Neovim 0.10+
* [`lewis6991/gitsigns.nvim`](https://github.com/lewis6991/gitsigns.nvim/)  (optional) for autoswitch on branch change

<a id="continuity-setup"></a>
## Setup

<a id="continuity-setup-nvim-pack"></a>
### Built-in plugin manager
```lua
vim.pack.add("https://github.com/lkubb/continuity.nvim")
vim.g.continuity_autosession = true -- optionally enable startup autosessions
vim.g.continuity_config = { --[[ custom options/overrides ]] }
```

<a id="continuity-setup-lazy-nvim"></a>
### lazy.nvim

<a id="continuity-setup-lazy-nvim-generally"></a>
#### Generally
```lua
{
  'lkubb/continuity.nvim',
  -- This plugin only ever loads as much as needed.
  -- You don't need to manage lazyloading manually.
  lazy = false,
  opts = {
    -- Custom options/overrides.
    -- Note: This ends up in `vim.g.continuity_config` (via `continuity.setup()`).
    --       Initialization is only triggered if you enable autosession-on-load
    --       and an autosession is defined for the current environment
    --       or once you invoke the continuity Lua API/Ex command.
  },
}
```

<a id="continuity-setup-lazy-nvim-autosession-on-startup"></a>
#### Autosession on startup
If you want to trigger autosession mode when Neovim starts, you need to set `g:continuity_autosession` **early**:
```lua
{
  'lkubb/continuity.nvim',
  init = function()
    vim.g.continuity_autosession = true
    vim.g.continuity_config = { --[[ custom options/overrides ]] }
  end,
}
```

<a id="continuity-configuration"></a>
## Configuration

<a id="continuity-configuration-defaults"></a>
### Defaults

```lua
{
  autosession = {
    config = {
      modified = false,
    },
    dir = "continuity",
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
    format = "[%(level)s %(time)s] %(message)%(src_sep)s[%(source_path)s:%(source_line)s]",
    notify_level = "warn",
    notify_format = "%(message)s",
    notify_opts = { title = "Continuity" },
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


<a id="continuity.UserConfig"></a>
### `continuity.UserConfig` (Class)

User configuration for this plugin.

**Fields:**

* **autosession**? [continuity.UserConfig.autosession](<#continuity.UserConfig.autosession>)

  Influence autosession behavior and contents

* **extensions**? `table<string,any>`

  Configuration for extensions, both Resession ones and those specific to Continuity.
  Note: Continuity first tries to load specified extensions in `continuity.extensions`,
  but falls back to `resession.extension` with a warning. Avoid this overhead
  by specifying `resession_compat = true` in the extension config.

* **load**? [continuity.UserConfig.load](<#continuity.UserConfig.load>)

  Configure session list information detail and sort order

* **log**? [continuity.UserConfig.log](<#continuity.UserConfig.log>)

  Configure plugin logging

* **session**? [continuity.UserConfig.session](<#continuity.UserConfig.session>)

  Influence session behavior and contents



<a id="continuity.UserConfig.autosession"></a>
### `continuity.UserConfig.autosession` (Class)

Configure autosession behavior and contents

**Fields:**

* **config**? [continuity.core.Session.InitOpts](<#continuity.core.Session.InitOpts>)

  Save/load configuration for autosessions

* **dir**? `string`

  Name of the directory to store autosession projects in.
  Interpreted relative to `$XDG_STATE_HOME/$NVIM_APPNAME`.

* **spec**? `fun(cwd: string) -> continuity.auto.AutosessionSpec?`
* **workspace**? `fun(cwd: string) -> (string,boolean)`
* **project_name**? `fun(workspace: string, git_info: continuity.auto.AutosessionSpec.GitInfo?) -> string`
* **session_name**? `fun(meta: {...}) -> string`
* **enabled**? `fun(meta: {...}) -> boolean`
* **load_opts**? `fun(meta: {...}) -> continuity.auto.LoadOpts?`


<a id="continuity.UserConfig.load"></a>
### `continuity.UserConfig.load` (Class)

Configure session list information detail and sort order

**Fields:**

* **detail**? `boolean`

  Show more detail about the sessions when selecting one to load.
  Disable if it causes lag.

* **order**? `("modification_time"|"creation_time"|"filename")`

  Session list order



<a id="continuity.UserConfig.log"></a>
### `continuity.UserConfig.log` (Class)

Configure plugin logging

**Fields:**

* **level**? [continuity.log.ConfigLevel](<#continuity.log.ConfigLevel>)

  Minimum level to log at. Defaults to `warn`.

* **notify_level**? [continuity.log.ConfigLevel](<#continuity.log.ConfigLevel>)

  Minimum level to use `vim.notify` for. Defaults to `warn`.

* **notify_opts**? `table`

  Options to pass to `vim.notify`. Defaults to `{ title = "Continuity" }`

* **format**? `string`

  Log line format string. Note that this works like Python's f-strings.
  Defaults to `[%(level)s %(time)s] %(message)%(src_sep)s[%(source_path)s:%(source_line)s]`.
  Available parameters:
  * `level` Uppercase level name
  * `dtime` Formatted date/time string
  * `hrtime` Time in `[ns]` without absolute anchor
  * `message` Log message
  * `src_sep` Whitespace between log line and source of call, 2 tabs for single line, newline + tab for multiline log messages
  * `src_path` Path to the file that called the log function
  * `src_line` Line in `src_path` that called the log function

* **notify_format**? `string`

  Same as `format`, but for `vim.notify` message display. Defaults to `%(message)s`.

* **time_format**? `string`

  `strftime` format string used for rendering time of call. Defaults to `%Y-%m-%d %H:%M:%S`

* **handler**? `fun(line: continuity.log.Line)`


<a id="continuity.UserConfig.session"></a>
### `continuity.UserConfig.session` (Class)

Configure default session behavior and contents, affects both manual and autosessions.

**Fields:**

* **autosave_enabled**? `boolean`

  When this session is attached, automatically save it in intervals. Defaults to false.

* **autosave_interval**? `integer`

  Seconds between autosaves of this session, if enabled. Defaults to 60.

* **autosave_notify**? `boolean`

  Trigger a notification when autosaving this session. Defaults to true.

* **on_attach**? [continuity.core.Session.AttachHook](<#continuity.core.Session.AttachHook>)

  A function that's called when attaching to this session. No global default.

* **on_detach**? [continuity.core.Session.DetachHook](<#continuity.core.Session.DetachHook>)

  A function that's called when detaching from this session. No global default.

* **options**? `string[]`

  Save and restore these neovim (global/buffer/tab/window) options

* **buf_filter**? `fun(bufnr: integer, opts: continuity.core.snapshot.CreateOpts) -> boolean`
* **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: continuity.core.snapshot.CreateOpts) -> boolean`
* **modified**? `(boolean|"auto")`

  Save/load modified buffers and their undo history.
  If set to `auto` (default), does not save, but still restores modified buffers.

* **jumps**? `boolean`

  Save/load window-specific jumplists, including current position
  (yes, for **all windows**, not just the active one like with ShaDa).
  If set to `auto` (default), does not save, but still restores saved jumplists.

* **changelist**? `boolean`

  Save/load buffer-specific changelist (all buffers) and
  changelist position (visible buffers only).

  **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
  Consider tracking `local_marks` in addition to this.

* **global_marks**? `boolean`

  Save/load global marks (A-Z, not 0-9 currently).

  _Only in global sessions._

* **local_marks**? `boolean`

  Save/load buffer-specific (local) marks.

  **Note**: Enable this if you track the `changelist`.

* **search_history**? `(integer|boolean)`

  Maximum number of search history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._

* **command_history**? `(integer|boolean)`

  Maximum number of command history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._

* **input_history**? `(integer|boolean)`

  Maximum number of input history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._

* **expr_history**? `boolean`

  Persist expression history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._

* **debug_history**? `boolean`

  Persist debug history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._

* **dir**? `string`

  Name of the directory to store regular sessions in.
  Interpreted relative to `$XDG_STATE_HOME/$NVIM_APPNAME`.


<a id="continuity-recipes"></a>
## Recipes

<a id="continuity-recipes-tab-scoped-sessions"></a>
### Tab-scoped Sessions
When saving a session, only save the current tab

```lua
-- Bind `save_tab` instead of `save`
local session = require("continuity.session")

vim.keymap.set("n", "<leader>ss", session.save_tab)
vim.keymap.set("n", "<leader>sl", session.load)
vim.keymap.set("n", "<leader>sd", session.delete)
```

This only saves the current tabpage layout, but _all_ of the open buffers.
You can provide a filter to exclude buffers.
For example, if you are using `:tcd` to have tabs open for different directories,
this only saves buffers in the current tabpage directory:

```lua
vim.g.continuity_config = {
  tab_buf_filter = function(tabpage, bufnr)
    local dir = vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tabpage))
    -- ensure dir has trailing /
    dir = dir:sub(-1) ~= "/" and dir .. "/" or dir
    return vim.startswith(vim.api.nvim_buf_get_name(bufnr), dir)
  end,
}
```

<a id="continuity-recipes-custom-extension"></a>
### Custom Extension
You can save custom session data with your own extension.

To create one, add a file to your runtimepath at `lua/continuity/extensions/<myplugin>.lua`.
Add the following contents:

```lua
local M = {}

--- Called when saving a session. Should return necessary state.
---@param opts (resession.Extension.OnSaveOpts & continuity.core.snapshot.Context)
---@param buflist continuity.core.snapshot.BufList
---@return any
M.on_save = function(opts, buflist)
  return {}
end

--- Called before restoring anything, receives the data returned by `on_save`.
---@param data any Data returned by `on_save`
---@param opts continuity.core.snapshot.Context
---@param buflist string[]
M.on_pre_load = function(data)
  -- This is run before the buffers, windows, and tabs are restored
end

--- Called after restoring everything, receives the data returned by `on_save`.
---@param data any Data returned by `on_save`
---@param opts continuity.core.snapshot.Context
---@param buflist string[]
M.on_post_load = function(data)
  -- This is run after the buffers, windows, and tabs are restored
end

--- Called when continuity gets configured.
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
--- Note: Continuity does not focus tabs or windows during session save,
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
---@param win continuity.core.layout.WinInfo
---@return integer? new_winid If the original window has been replaced, return the new ID that should replace it
M.load_win = function(winid, config, win)
  -- Restore the window from the config
end

return M
```

Enable your extension by adding a corresponding key in the `extensions` option:

```lua
vim.g.continuity_config = {
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
vim.g.continuity_config = {
  -- ...
  extensions = {
    myplugin = {
      enable_in_tab = true,
    },
  }
}
```

<a id="continuity-api"></a>
## API

<a id="continuity-api-manual-sessions"></a>
### Manual Sessions


<a id="continuity.session"></a>
#### `continuity.session` (Class)

Interactive API, (mostly) compatible with stevearc/resession.nvim.

<a id="continuity.session.save()"></a>
##### save(`name`, `opts`)

Save the current global state to disk

**Parameters:**
  * **name**? `string`

    Name of the global session to save.
    If not provided, takes name of attached one or prompts user.

  * **opts**? `(continuity.session.SaveOpts & continuity.core.PassthroughOpts)`

    Table fields:

    * **dir**? `string`

      Name of session directory (overrides config.dir)

    * **autosave_enabled**? `boolean`

      When this session is attached, automatically save it in intervals. Defaults to false.

    * **autosave_interval**? `integer`

      Seconds between autosaves of this session, if enabled. Defaults to 60.

    * **autosave_notify**? `boolean`

      Trigger a notification when autosaving this session. Defaults to true.

    * **on_attach**? [continuity.core.Session.AttachHook](<#continuity.core.Session.AttachHook>)

      A function that's called when attaching to this session. No global default.

    * **on_detach**? [continuity.core.Session.DetachHook](<#continuity.core.Session.DetachHook>)

      A function that's called when detaching from this session. No global default.

    * **options**? `string[]`

      Save and restore these neovim (global/buffer/tab/window) options

    * **buf_filter**? `fun(bufnr: integer, opts: continuity.core.snapshot.CreateOpts) -> boolean`
    * **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: continuity.core.snapshot.CreateOpts) -> boolean`
    * **modified**? `(boolean|"auto")`

      Save/load modified buffers and their undo history.
      If set to `auto` (default), does not save, but still restores modified buffers.

    * **jumps**? `boolean`

      Save/load window-specific jumplists, including current position
      (yes, for **all windows**, not just the active one like with ShaDa).
      If set to `auto` (default), does not save, but still restores saved jumplists.

    * **changelist**? `boolean`

      Save/load buffer-specific changelist (all buffers) and
      changelist position (visible buffers only).

      **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
      Consider tracking `local_marks` in addition to this.

    * **global_marks**? `boolean`

      Save/load global marks (A-Z, not 0-9 currently).

      _Only in global sessions._

    * **local_marks**? `boolean`

      Save/load buffer-specific (local) marks.

      **Note**: Enable this if you track the `changelist`.

    * **search_history**? `(integer|boolean)`

      Maximum number of search history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._

    * **command_history**? `(integer|boolean)`

      Maximum number of command history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._

    * **input_history**? `(integer|boolean)`

      Maximum number of input history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._

    * **expr_history**? `boolean`

      Persist expression history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._

    * **debug_history**? `boolean`

      Persist debug history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._

    * **meta**? `table`

      External data remembered in association with this session. Useful to build on top of the core API.

    * **attach**? `boolean`

      Attach to/stay attached to session after operation

    * **notify**? `boolean`

      Notify on success

    * **reset**? `boolean`

      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.


<a id="continuity.session.save_tab()"></a>
##### save_tab(`name`, `opts`)

Save the state of the current tabpage to disk

**Parameters:**
  * **name**? `string`

    Name of the tabpage session to save.
    If not provided, takes name of attached one in current tabpage or prompts user.

  * **opts**? `(continuity.session.SaveOpts & continuity.core.PassthroughOpts)`

    Table fields:

    * **dir**? `string`

      Name of session directory (overrides config.dir)

    * **autosave_enabled**? `boolean`

      When this session is attached, automatically save it in intervals. Defaults to false.

    * **autosave_interval**? `integer`

      Seconds between autosaves of this session, if enabled. Defaults to 60.

    * **autosave_notify**? `boolean`

      Trigger a notification when autosaving this session. Defaults to true.

    * **on_attach**? [continuity.core.Session.AttachHook](<#continuity.core.Session.AttachHook>)

      A function that's called when attaching to this session. No global default.

    * **on_detach**? [continuity.core.Session.DetachHook](<#continuity.core.Session.DetachHook>)

      A function that's called when detaching from this session. No global default.

    * **options**? `string[]`

      Save and restore these neovim (global/buffer/tab/window) options

    * **buf_filter**? `fun(bufnr: integer, opts: continuity.core.snapshot.CreateOpts) -> boolean`
    * **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: continuity.core.snapshot.CreateOpts) -> boolean`
    * **modified**? `(boolean|"auto")`

      Save/load modified buffers and their undo history.
      If set to `auto` (default), does not save, but still restores modified buffers.

    * **jumps**? `boolean`

      Save/load window-specific jumplists, including current position
      (yes, for **all windows**, not just the active one like with ShaDa).
      If set to `auto` (default), does not save, but still restores saved jumplists.

    * **changelist**? `boolean`

      Save/load buffer-specific changelist (all buffers) and
      changelist position (visible buffers only).

      **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
      Consider tracking `local_marks` in addition to this.

    * **global_marks**? `boolean`

      Save/load global marks (A-Z, not 0-9 currently).

      _Only in global sessions._

    * **local_marks**? `boolean`

      Save/load buffer-specific (local) marks.

      **Note**: Enable this if you track the `changelist`.

    * **search_history**? `(integer|boolean)`

      Maximum number of search history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._

    * **command_history**? `(integer|boolean)`

      Maximum number of command history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._

    * **input_history**? `(integer|boolean)`

      Maximum number of input history items to persist. Defaults to false.
      If set to `true`, maps to the `'history'` option.

      _Only in global sessions._

    * **expr_history**? `boolean`

      Persist expression history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._

    * **debug_history**? `boolean`

      Persist debug history. Defaults to false.
      **Note**: Cannot set limit (currently), no direct support by neovim.

      _Only in global sessions._

    * **meta**? `table`

      External data remembered in association with this session. Useful to build on top of the core API.

    * **attach**? `boolean`

      Attach to/stay attached to session after operation

    * **notify**? `boolean`

      Notify on success

    * **reset**? `boolean`

      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.


<a id="continuity.session.save_all()"></a>
##### save_all(`opts`)

**Parameters:**
  * **opts** `unknown`

<a id="continuity.session.load()"></a>
##### load(`name`, `opts`)

Load a session from disk

**Attributes:**
  * note

**Parameters:**
  * **name**? `string`

    Name of the session to load from session dir.
    If not provided, prompts user.

  * **opts**? `(continuity.session.LoadOpts & continuity.core.PassthroughOpts)`

    attach? boolean Stay attached to session after loading (default true)
    reset? boolean|"auto" Close everything before loading the session (default "auto")
    silence_errors? boolean Don't error when trying to load a missing session
    dir? string Name of directory to load from (overrides config.dir)


<a id="continuity.session.detach()"></a>
##### detach(`target`, `reason`, `opts`)

M.get_current = Manager.get_current
M.get_current_data = Manager.get_current_data

**Parameters:**
  * **target**? `("__global"|"__active"|"__active_tab"|"__all_tabs"|string|integer...)`

    The scope/session name/tabid to detach from. If unspecified, detaches all sessions.

  * **reason**? `continuity.core.Session.DetachReason`

    Pass a custom reason to detach handlers. Defaults to `request`.

  * **opts**? `(continuity.core.Session.DetachOpts & continuity.core.PassthroughOpts)`

    Table fields:

    * **reset**? `boolean`

      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.

    * **save**? `boolean`

      Save/override autosave config for affected sessions before the operation


**Returns:** **detached** `boolean`

Whether we detached from any session


<a id="continuity.session.list()"></a>
##### list(`opts`)

List all available saved sessions in session dir

**Parameters:**
  * **opts** `unknown`

**Returns:** **sessions_in_dir** `string[]`

<a id="continuity.session.delete()"></a>
##### delete(`name`, `opts`)

Delete a saved session from session dir

**Parameters:**
  * **name**? `string`

    Name of the session. If not provided, prompts user

  * **opts**? `(continuity.session.DeleteOpts & continuity.core.PassthroughOpts)`

    Table fields:

    * **dir**? `string`

      Name of session directory (overrides config.dir)

    * **notify**? `boolean`

      Notify on success

    * **reset**? `boolean`

      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.

    * **silence_errors**? `boolean`

      Don't error during this operation


<a id="continuity-api-autosessions"></a>
### Autosessions


<a id="continuity.auto"></a>
#### `continuity.auto` (Class)

<a id="continuity.auto.save()"></a>
##### save(`opts`)

Save the currently active autosession.

**Parameters:**
  * **opts**? `(continuity.auto.SaveOpts & continuity.core.PassthroughOpts)`

    Table fields:

    * **attach**? `boolean`

      Attach to/stay attached to session after operation

    * **notify**? `boolean`

      Notify on success

    * **reset**? `boolean`

      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.


<a id="continuity.auto.detach()"></a>
##### detach(`opts`)

Detach from the currently active autosession.
If autosave is enabled, save it. Optionally close **everything**.

**Parameters:**
  * **opts**? `(continuity.core.Session.DetachOpts & continuity.core.PassthroughOpts)`

    Table fields:

    * **reset**? `boolean`

      When detaching a session in the process, unload associated resources/reset
      everything during the operation when restoring a snapshot.

    * **save**? `boolean`

      Save/override autosave config for affected sessions before the operation


<a id="continuity.auto.load()"></a>
##### load(`autosession`, `opts`)

Load an autosession.

**Parameters:**
  * **autosession**? `(continuity.auto.AutosessionContext|string)`

    The autosession table as rendered by `get_ctx` or cwd to pass to it

  * **opts**? `continuity.auto.LoadOpts`

<a id="continuity.auto.reload()"></a>
##### reload()

If an autosession is active, save it and detach.
Then try to start a new one.

<a id="continuity.auto.start()"></a>
##### start(`cwd`, `opts`)

Start Continuity:
1. If the current working directory has an associated project and session,
closes everything and loads that session.
2. In any case, start monitoring for directory or branch changes.

**Parameters:**
  * **cwd**? `string`

    Working directory to switch to before starting autosession. Defaults to nvim's process' cwd.

  * **opts**? `continuity.auto.LoadOpts`

<a id="continuity.auto.stop()"></a>
##### stop()

Stop Continuity:
1. If we're inside an active autosession, save it and detach.
Keep buffers/windows/tabs etc. by default.
2. In any case, stop monitoring for directory or branch changes.

<a id="continuity.auto.reset()"></a>
##### reset(`opts`)

Delete the currently active autosession. Close **everything**.
Attempt to start a new autosession (optionally).

**Parameters:**
  * **opts**? `continuity.auto.ResetOpts`

<a id="continuity.auto.reset_project()"></a>
##### reset_project(`opts`)

Remove all autosessions associated with a project.
If the target is the active project, reset current session as well and close **everything**.

**Parameters:**
  * **opts**? `continuity.auto.ResetProjectOpts`

<a id="continuity.auto.list()"></a>
##### list(`opts`)

List autosessions associated with a project.

**Parameters:**
  * **opts**? `continuity.auto.ListOpts`

    Specify the project to list.
    If unspecified, lists active project, if available.


**Returns:** **session_names** `string[]`

List of known sessions associated with project


<a id="continuity.auto.list_projects()"></a>
##### list_projects(`opts`)

List all known projects.

**Parameters:**
  * **opts**? `continuity.auto.ListProjectOpts`

**Returns:** `string[]`

<a id="continuity.auto.migrate_projects()"></a>
##### migrate_projects(`opts`)

Dev helper currently (beware: unstable/inefficient).
When changing the mapping from workspace to project name, all previously
saved states would be lost. This tries to migrate state data to the new mapping,
cleans projects whose cwd does not exist anymore or which are disabled
Caution! This does not account for projects with multiple associated directories/sessions!
Checks the first session's cwd/enabled state only!

**Parameters:**
  * **opts**? `continuity.auto.MigrateProjectsOpts`

    Options for migration. You need to pass `{dry_run = false}`
    for this function to have an effect.


**Returns:** **migration_result** `table<("broken"|"missing"|"skipped"|"migrated"...),table[]>`

<a id="continuity.auto.info()"></a>
##### info(`opts`)

Return information about the currently active session.
Includes autosession information, if it is an autosession.

**Parameters:**
  * **opts**? `{ with_snapshot: boolean? }`

    Table fields:

    * **with_snapshot**? `boolean`

**Returns:** **active_info**? `continuity.auto.ActiveAutosessionInfo`

Information about the active session, even if not an autosession.
Always includes snapshot configuration, session meta config and
whether it is an autosession. For autosessions, also includes
autosession config.


<a id="continuity-api-relevant-types"></a>
### Relevant Types


<a id="continuity.core.Session.InitOpts"></a>
#### `continuity.core.Session.InitOpts` (Alias)

**Type:** `(continuity.core.Session.Init.Autosave & continuity.core.Session.Init.Hooks & continuity.core.snapshot.CreateOpts)`

Options to influence how an attached session is handled.

**Fields:**

* **autosave_enabled**? `boolean`

  When this session is attached, automatically save it in intervals. Defaults to false.

* **autosave_interval**? `integer`

  Seconds between autosaves of this session, if enabled. Defaults to 60.

* **autosave_notify**? `boolean`

  Trigger a notification when autosaving this session. Defaults to true.

* **on_attach**? [continuity.core.Session.AttachHook](<#continuity.core.Session.AttachHook>)

  A function that's called when attaching to this session. No global default.

* **on_detach**? [continuity.core.Session.DetachHook](<#continuity.core.Session.DetachHook>)

  A function that's called when detaching from this session. No global default.

* **options**? `string[]`

  Save and restore these neovim (global/buffer/tab/window) options

* **buf_filter**? `fun(bufnr: integer, opts: continuity.core.snapshot.CreateOpts) -> boolean`
* **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: continuity.core.snapshot.CreateOpts) -> boolean`
* **modified**? `(boolean|"auto")`

  Save/load modified buffers and their undo history.
  If set to `auto` (default), does not save, but still restores modified buffers.

* **jumps**? `boolean`

  Save/load window-specific jumplists, including current position
  (yes, for **all windows**, not just the active one like with ShaDa).
  If set to `auto` (default), does not save, but still restores saved jumplists.

* **changelist**? `boolean`

  Save/load buffer-specific changelist (all buffers) and
  changelist position (visible buffers only).

  **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
  Consider tracking `local_marks` in addition to this.

* **global_marks**? `boolean`

  Save/load global marks (A-Z, not 0-9 currently).

  _Only in global sessions._

* **local_marks**? `boolean`

  Save/load buffer-specific (local) marks.

  **Note**: Enable this if you track the `changelist`.

* **search_history**? `(integer|boolean)`

  Maximum number of search history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._

* **command_history**? `(integer|boolean)`

  Maximum number of command history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._

* **input_history**? `(integer|boolean)`

  Maximum number of input history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._

* **expr_history**? `boolean`

  Persist expression history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._

* **debug_history**? `boolean`

  Persist debug history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._




<a id="continuity.core.Session.InitOptsWithMeta"></a>
#### `continuity.core.Session.InitOptsWithMeta` (Alias)

**Type:** `(continuity.core.Session.InitOpts & continuity.core.Session.Init.Meta)`

Options to influence how an attached session is handled plus `meta` field, which can only be populated by passing
it to the session constructor and is useful for custom session handling.

**Fields:**

* **autosave_enabled**? `boolean`

  When this session is attached, automatically save it in intervals. Defaults to false.

* **autosave_interval**? `integer`

  Seconds between autosaves of this session, if enabled. Defaults to 60.

* **autosave_notify**? `boolean`

  Trigger a notification when autosaving this session. Defaults to true.

* **on_attach**? [continuity.core.Session.AttachHook](<#continuity.core.Session.AttachHook>)

  A function that's called when attaching to this session. No global default.

* **on_detach**? [continuity.core.Session.DetachHook](<#continuity.core.Session.DetachHook>)

  A function that's called when detaching from this session. No global default.

* **options**? `string[]`

  Save and restore these neovim (global/buffer/tab/window) options

* **buf_filter**? `fun(bufnr: integer, opts: continuity.core.snapshot.CreateOpts) -> boolean`
* **tab_buf_filter**? `fun(tabpage: integer, bufnr: integer, opts: continuity.core.snapshot.CreateOpts) -> boolean`
* **modified**? `(boolean|"auto")`

  Save/load modified buffers and their undo history.
  If set to `auto` (default), does not save, but still restores modified buffers.

* **jumps**? `boolean`

  Save/load window-specific jumplists, including current position
  (yes, for **all windows**, not just the active one like with ShaDa).
  If set to `auto` (default), does not save, but still restores saved jumplists.

* **changelist**? `boolean`

  Save/load buffer-specific changelist (all buffers) and
  changelist position (visible buffers only).

  **Important**: Enabling this causes **buffer-local marks to be cleared** during restoration.
  Consider tracking `local_marks` in addition to this.

* **global_marks**? `boolean`

  Save/load global marks (A-Z, not 0-9 currently).

  _Only in global sessions._

* **local_marks**? `boolean`

  Save/load buffer-specific (local) marks.

  **Note**: Enable this if you track the `changelist`.

* **search_history**? `(integer|boolean)`

  Maximum number of search history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._

* **command_history**? `(integer|boolean)`

  Maximum number of command history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._

* **input_history**? `(integer|boolean)`

  Maximum number of input history items to persist. Defaults to false.
  If set to `true`, maps to the `'history'` option.

  _Only in global sessions._

* **expr_history**? `boolean`

  Persist expression history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._

* **debug_history**? `boolean`

  Persist debug history. Defaults to false.
  **Note**: Cannot set limit (currently), no direct support by neovim.

  _Only in global sessions._

* **meta**? `table`

  External data remembered in association with this session. Useful to build on top of the core API.




<a id="continuity.core.Session.AttachHook"></a>
#### `continuity.core.Session.AttachHook` (Alias)

**Type:** `fun(session: continuity.core.IdleSession)`

Attach hooks can inspect the session.
Modifying it in-place should work, but it's not officially supported.



<a id="continuity.core.Session.DetachHook"></a>
#### `continuity.core.Session.DetachHook` (Alias)

**Type:** `(fun(session: continuity.core.ActiveSession, reason: continuity.core.Session.DetachReason, opts: (continuity.core.Session.DetachOpts & continuity.core.PassthroughOpts)) -> (continuity.core.Session.DetachOpts & continuity.core.PassthroughOpts))?`

Detach hooks can modify detach opts in place or return new ones.
They can inspect the session. Modifying it in-place should work, but it's not officially supported.


<a id="continuity-extensions"></a>
## Extensions

<a id="continuity-extensions-built-in"></a>
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

<a id="continuity-extensions-external"></a>
### External
Here are some examples of external extensions:

* [**aerial.nvim**](https://github.com/stevearc/aerial.nvim):

  Note: For Resession, which is compatible with Continuity.

* [**overseer.nvim**](https://github.com/stevearc/overseer.nvim):

  Note: For Resession, which is compatible with Continuity.

<a id="continuity-faq"></a>
## FAQ
**Q: Why another session plugin?**

A1: All the other plugins (with the exception of `resession.nvim`)
    use `:mksession` under the hood
A2: Resession cannot be bent enough via its interface to support everything
    Continuity does. Its API is difficult to build another plugin on top of
    (e.g. cannot get session table without Resession saving it to a file
    first).

**Q: Why don't you want to use `:mksession`?**

A: While it's amazing that this feature is built-in to vim, and it does an
   impressively good job for most situations, it is very difficult to
   customize. If `:help sessionoptions` covers your use case, then you're
   golden. If you want anything else, you're out of luck.
