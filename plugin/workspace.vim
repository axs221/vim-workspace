" Vim plugin
" Author:  Thaer Khawaja
" License: Apache 2.0
" URL:     https://github.com/thaerkh/vim-workspace

let g:workspace_session_name = get(g:, 'workspace_session_name', 'Session.vim')
let g:workspace_undodir = get(g:, 'workspace_undodir', '.undodir')
let g:workspace_persist_undo_history = get(g:, 'workspace_persist_undo_history', 1)
let g:workspace_autosave = get(g:, 'workspace_autosave', 1)
let g:workspace_autosave_always = get(g:, 'workspace_autosave_always', 0)
let g:workspace_autosave_ignore = get(g:, 'workspace_autosave_ignore', ['gitcommit', 'gitrebase'])
let g:workspace_autosave_untrailspaces = get(g:, 'workspace_autosave_untrailspaces', 1)
let g:workspace_autosave_au_updatetime = get(g:, 'workspace_autosave_au_updatetime', 4)
let g:workspace_sensible_settings = get(g:, 'workspace_sensible_settings', 0)
let g:workspace_autocreate = get(g:, 'workspace_autocreate', 0)


function! s:SetSensibleSettings()
  " Needed for plugin features
  set completeopt=menuone,longest,preview
  set encoding=utf-8
  set sessionoptions-=options

  if g:workspace_sensible_settings
    " Environment behaviour
    filetype plugin indent on
    syntax on
    set nocompatible
    set clipboard=unnamedplus
    set complete-=i
    set path+=**
    set updatetime=1000
    set wildmenu
    set wildmode=list:longest,full

    if !has('nvim')
      set swapsync=""
    endif

    " Editor view
    set foldmethod=indent
    set nofoldenable
    set incsearch
    set laststatus=2
    set linebreak
    set list
    set listchars=extends:>,precedes:<,tab:\|\ ,trail:·
    set number
    set ruler

    " Editing behaviour
    set autoindent
    set backspace=indent,eol,start
    set smarttab

    nnoremap Q <Nop>
  endif
endfunction

function! s:WorkspaceExists()
  return filereadable(g:workspace_session_name)
endfunction

function! s:MakeWorkspace(workspace_save_session)
  if a:workspace_save_session == 1 || get(s:, 'workspace_save_session', 0) == 1
    let s:workspace_save_session = 1
    execute printf('mksession! %s/%s', getcwd(), g:workspace_session_name)
  endif
endfunction

function! s:FindOrNew(filename)
  let a:bufnr = bufnr(a:filename)
  for tabnr in range(1, tabpagenr("$"))
    for bufnr in tabpagebuflist(tabnr)
      if (bufnr == a:bufnr)
        execute 'tabn ' . tabnr
        call win_gotoid(win_findbuf(a:bufnr)[0])
        return
      endif
    endfor
  endfor
  tabnew
  execute 'buffer ' . a:bufnr
endfunction

function! s:CloseHiddenBuffers()
  let a:visible_buffers = {}
  for tabnr in range(1, tabpagenr('$'))
    for bufnr in tabpagebuflist(tabnr)
      let a:visible_buffers[bufnr] = 1
    endfor
  endfor

  for bufnr in range(1, bufnr('$'))
    if bufexists(bufnr) && !has_key(a:visible_buffers,bufnr)
      execute printf('bwipeout %d', bufnr)
    endif
  endfor
endfunction

function! s:ConfigureWorkspace()
  call s:SetUndoDir()
  call s:SetAutosave(1)
endfunction

function! s:RemoveWorkspace()
  let s:workspace_save_session  = 0
  execute printf('call delete("%s")', g:workspace_session_name)
  if !g:workspace_autosave_always
    call s:SetAutosave(0)
  endif
endfunction

function! s:ToggleWorkspace()
  if s:WorkspaceExists()
    call s:RemoveWorkspace()
    execute printf('silent !rm -rf %s', g:workspace_undodir)
    call feedkeys("") | silent! redraw!  " Recover view from external comand
    echo 'Workspace removed!'
  else
    call s:MakeWorkspace(1)
    call s:ConfigureWorkspace()
    echo 'Workspace created!'
  endif
endfunction

function! s:LoadWorkspace()
  if index(g:workspace_autosave_ignore, &filetype) != -1
    return
  endif

  if s:WorkspaceExists()
    let s:workspace_save_session = 1
    let a:filename = expand(@%)
    execute 'source ' . g:workspace_session_name
    call s:ConfigureWorkspace()
    call s:FindOrNew(a:filename)
  else
    if g:workspace_autocreate
      call s:ToggleWorkspace()
    else
      let s:workspace_save_session = 0
    endif
  endif
endfunction

function! s:UntrailSpaces()
  if g:workspace_autosave_untrailspaces && &modifiable
    let curr_row = line('.')
    let curr_col = virtcol('.')
    :%s/\ \+$//e
    cal cursor(curr_row, curr_col)
  endif
endfunction

function! s:Autosave(timed)
  if index(g:workspace_autosave_ignore, &filetype) != -1 || &readonly || mode() == 'c' || pumvisible()
    return
  endif

  let current_time = localtime()
  let s:last_update = get(s:, 'last_update', 0)
  let s:time_delta = current_time - s:last_update

  if a:timed == 0 || s:time_delta >= 1
    let s:last_update = current_time
    checktime  " checktime with autoread will sync files on a last-writer-wins basis.
    call s:UntrailSpaces()
    silent! update  " only updates if there are changes to the file.
    if a:timed == 0 || s:time_delta >= g:workspace_autosave_au_updatetime
      doautocmd BufWritePost %  " Periodically trigger BufWritePost.
    endif
  endif
endfunction

function! s:SetAutosave(enable)
  if !g:workspace_autosave
    return
  endif
  if a:enable == 1
    set autoread
    set autowrite
    augroup WorkspaceToggle
      au! BufLeave,FocusLost,FocusGained,InsertLeave * call s:Autosave(0)
      au! CursorHold * call s:Autosave(1)
      au! BufEnter * call s:MakeWorkspace(0)
    augroup END
    let s:autosave_on = 1
  else
    set noautoread
    set noautowrite
    au! WorkspaceToggle * *
    let s:autosave_on = 0
  endif
endfunction

function! s:ToggleAutosave()
  if get(s:, 'autosave_on', 0)
    call s:SetAutosave(0)
    echo 'Autosave disabled!'
  else
    call s:SetAutosave(1)
    echo 'Autosave enabled!'
  endif
endfunction

function! s:SetUndoDir()
  if g:workspace_persist_undo_history
    if !isdirectory(g:workspace_undodir)
      call mkdir(g:workspace_undodir)
    endif
    execute 'set undodir=' . resolve(g:workspace_undodir)
    set undofile
  endif
endfunction

function! s:PostLoadCleanup()
  if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
endfunction

augroup Workspace
  au! VimEnter * nested call s:LoadWorkspace()
  au! VimLeave * call s:MakeWorkspace(0)
  au! InsertLeave * if pumvisible() == 0|pclose|endif
  au! SessionLoadPost * call s:PostLoadCleanup()
augroup END

augroup WorkspaceAutosave
  au! VimEnter * if g:workspace_autosave_always == 1 | call s:SetAutosave(1) | endif
augroup END

command! ToggleAutosave call s:ToggleAutosave()
command! ToggleWorkspace call s:ToggleWorkspace()
command! CloseHiddenBuffers call s:CloseHiddenBuffers()

call s:SetSensibleSettings()

" vim: ts=2 sw=2 et
