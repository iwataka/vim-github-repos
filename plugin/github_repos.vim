if !has('ruby')
  finish
endif

if exists("g:loaded_github_repos_plugin")
  finish
endif
let g:loaded_github_repos_plugin = 1

command! -nargs=* -complete=customlist,github_repos#autocomplete -bang GHStarred  call github_repos#open('!' != '<bang>', 'starred', <f-args>)
command! -nargs=* -complete=customlist,github_repos#autocomplete -bang GHSearch call github_repos#open('!' != '<bang>', 'search', <f-args>)
