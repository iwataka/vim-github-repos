let s:save_cpo = &cpoptions
set cpoptions&vim

let s:passwords  = {}
let s:more_line  = '   -- MORE --'
let s:not_loaded = ''
let s:history    = { 'starred': {}, 'search': {} }
let s:basedir    = expand('<sfile>:p:h')

let s:is_mac =
  \ has('mac') ||
  \ has('macunix') ||
  \ executable('uname') &&
  \ index(['Darwin', 'Mac'], substitute(system('uname'), '\n', '', '')) != -1
let s:is_win = has('win32') || has('win64')

let s:original_statusline = &statusline

function! s:password(profile, username)
  let fromopt = s:option(a:profile, 'password', '')
  return empty(fromopt) ? get(s:passwords, a:profile.'/'.a:username, '') : fromopt
endfunction

function! s:remember_password(profile, username, password)
  let s:passwords[a:profile.'/'.a:username] = a:password
endfunction

function! s:forget_password(profile, username)
  silent! call remove(s:passwords, a:profile.'/'.a:username)
endfunction

function! s:option(...)
  if a:0 == 2
    let profile = get(b:, 'github_profile', '')
    let [key, default] = a:000
  elseif a:0 == 3
    let [profile, key, default] = a:000
  endif

  let options = get(g:, 'github_repos' . (empty(profile) ? '' : ('#' . profile)), {})
  return get(options, key, default)
endfunction

function! s:init_tab(...)
  let b:github_index = 0
  let b:github_error = 0
  let b:github_links = {}
  let b:github_api_endpoint = s:option('api_endpoint', 'https://api.github.com')
  let b:github_web_endpoint = s:option('web_endpoint', 'https://github.com')

  if a:0 == 2
    setlocal buftype=nofile noswapfile nowrap nonu cursorline foldmethod=syntax
    call s:define_maps()
    setf github-repos

    let [what, type] = a:000
    if type == 'starred'
      let b:github_init_url = b:github_api_endpoint.'/users/'.what.'/starred'
      let b:github_statusline = ['Starred', what]
    elseif type == 'search'
      let query = join(split(what), '+')
      let b:github_init_url = b:github_api_endpoint.'/search/repositories?q='.query
      let b:github_statusline = ['Search', what]
    else
      echoerr 'Invalid type'
      return 0
    endif

    " Assign buffer name
    let bufname_prefix = '['.what.']'
    let bufname = bufname_prefix
    let bufidx = 2
    while buflisted(bufname)
      let bufname = bufname_prefix.'('.bufidx.')'
      let bufidx += 1
    endwhile
    silent! execute 'f '.fnameescape(bufname)
  endif
  let b:github_more_url = b:github_init_url

  if s:option('statusline', 1)
    setlocal statusline=%!github_repos#statusline()
  endif

  syntax clear
  syntax region githubTitle start=/^ \{0,2}[0-9]/ end="\n" oneline contains=githubNumber,Keyword,githubRepo,githubUser,githubTime,githubRef,githubCommit,githubTag,githubBranch,githubGist,githubRelease
  syntax match githubNumber /^ \{0,2}[0-9]\{-1,})/ contained
  syntax match githubTime   /(.\{-1,})$/ contained
  syntax match githubSHA    /^\s\+\[[0-9a-fA-F]\{4,}\]/
  syntax match githubEdit   /\(^\s\+Edited \)\@<=\[.\{-}\]/
  syntax match githubUser   /\[[^/\]]\{-1,}\]/ contained
  syntax match githubRepo   /\[[^/\]]\{-1,}\/[^/\]@]\{-1,}\]/ contained
  syntax match githubCommit /\[[^/\]]\{-1,}\/[^/\]@]\{-1,}@[0-9a-fA-Z]\{-1,}\]/ contained
  syntax match githubTag    /\(tag \)\@<=\[.\{-1,}\]/ contained
  syntax match githubBranch /\(branch \)\@<=\[.\{-1,}\]/ contained
  syntax match githubBranch /\(pushed to \)\@<=\[.\{-1,}\]/ contained
  syntax match githubGist   /\(a gist \)\@<=\[.\{-1,}\]/ contained
  syntax match githubRelease /\(released \)\@<=\[.\{-1,}\]/ contained

  syntax region githubFoldBlock start=/\%(\_^ \{4,}.*\n\)\{5}/ms=s+1 end=/\%(^ \{,4}\S\)\@=/ contains=githubFoldBlockLine2
  syntax region githubFoldBlockLine2 start=/^ \{4,}/ms=e+1 end=/\%(^ \{,4}\S\)\@=/ contained contains=githubFoldBlockLine3 keepend
  syntax region githubFoldBlockLine3 start=/^ \{4,}/ms=e+1 end=/\%(^ \{,4}\S\)\@=/ contained contains=githubFoldBlockLine4 keepend
  syntax region githubFoldBlockLine4 start=/^ \{4,}/ms=e+1 end=/\%(^ \{,4}\S\)\@=/ contained contains=githubFoldBlockLine5 keepend
  syntax region githubFoldBlockLine5 start=/^ \{4,}/ms=e+1 end=/\%(^ \{,4}\S\)\@=/ contained keepend fold

  hi def link githubNumber  Number
  hi def link githubUser    String
  hi def link githubRepo    Identifier
  hi def link githubRef     Special
  hi def link githubRelease Label
  hi def link githubTag     Label
  hi def link githubBranch  Label
  hi def link githubEdit    Constant
  hi def link githubTime    Comment
  hi def link githubSHA     Float
  hi def link githubCommit  Special
  hi def link githubGist    Identifier
  execute 'syntax match githubKeyword /'.s:more_line.'/'
  syntax match githubKeyword /^Loading.*/
  syntax match githubKeyword /^Reloading.*/
  syntax match githubFailure /^Failed.*/
  hi def link githubKeyword Conditional
  hi def link githubFailure Exception

  return 1
endfunction

function! s:refresh()
  call s:init_tab()
  setlocal modifiable
  normal! gg"_dG
  setlocal nomodifiable

  try
    call s:call_ruby('Reloading GitHub event stream ...')
  catch
    let b:github_error = 1
  endtry
  if b:github_error
    call setline(line('$'), 'Failed to load events. Press R to reload.')
    setlocal nomodifiable
    return
  endif
endfunction

function! s:open(profile, what, type)
  let pos = s:option('position', 'tab')
  if pos ==? 'tab'
    tabnew
  elseif pos ==? 'top'
    topleft new
  elseif pos ==? 'bottom'
    botright new
  elseif pos ==? 'above'
    aboveleft new
  elseif pos ==? 'below'
    belowright new
  elseif pos ==? 'left'
    vertical new
  elseif pos ==? 'right'
    vertical rightbelow new
  else
    echoerr "Invalid position: ". pos
    tabnew
    return 0
  endif

  let b:github_profile = a:profile
  return s:init_tab(a:what, a:type)
endfunction

function! s:call_ruby(msg)
  if !empty(s:not_loaded)
    echoerr s:not_loaded
    return
  endif

  setlocal modifiable
  call setline(line('$'), a:msg)
  redraw!
  ruby GitHubRepos.more
  if !b:github_error
    setlocal nomodifiable
  end
  syntax sync minlines=0
endfunction

function! github_repos#open(auth, type, ...)
  if !empty(s:not_loaded)
    echoerr s:not_loaded
    return
  endif

  let profile = substitute(get(filter(copy(a:000), 'stridx(v:val, "-") == 0'), -1, ''), '^-*', '', '')
  if !empty(profile) && !exists('g:github_repos#'.profile)
    echoerr 'Profile not defined: '. profile
    return
  endif

  let args = filter(copy(a:000), 'stridx(v:val, "-") != 0')
  let username = s:option(profile, 'username', '')
  if a:auth
    if empty(username)
      call inputsave()
      let username = input('Enter GitHub username: ')
      call inputrestore()
      if empty(username) | echo "Empty username" | return | endif
    endif

    let password = s:password(profile, username)
    if empty(password)
      call inputsave()
      let password = inputsecret('Enter GitHub password: ')
      call inputrestore()
      if empty(password) | echo "Empty password" | return | endif
      call s:remember_password(profile, username, password)
    endif
  else
    let password = ''
  endif

  let who = get(args, 0, username)
  if empty(who) | echo "Username not given" | return | endif

  if !s:open(profile, who, a:type)
    bd
    return
  endif

  let b:github_username = username
  let b:github_password = password

  try
    call s:call_ruby('Loading GitHub event stream ...')
  catch /^Vim:Interrupt$/
    bd
    return
  catch
    bd
    throw 'Error: '.v:exception
  endtry

  let s:history[a:type][who] = 1
endfunction

function! s:define_maps()
  nnoremap <silent> <buffer> <Plug>(ghd-quit)     :<C-u>bd<cr>
  nnoremap <silent> <buffer> <Plug>(ghd-refresh)  :<C-u>call <SID>refresh()<cr>
  nnoremap <silent> <buffer> <Plug>(ghd-action)   :<C-u>call <SID>action()<cr>
  nnoremap <silent> <buffer> <Plug>(ghd-action)   :<C-u>call <SID>action()<cr>
  nnoremap <silent> <buffer> <Plug>(ghd-action)   :<C-u>call <SID>action()<cr>
  nnoremap <silent> <buffer> <Plug>(ghd-next)     :<C-u>silent! call <SID>next_item('')<cr>
  nnoremap <silent> <buffer> <Plug>(ghd-prev)     :<C-u>silent! call <SID>next_item('b')<cr>
  nnoremap <silent> <buffer> <Plug>(ghd-clone)    :<C-u>silent! call <SID>clone()<cr>
  nmap <silent> <buffer> q             <Plug>(ghd-quit)
  nmap <silent> <buffer> R             <Plug>(ghd-refresh)
  nmap <silent> <buffer> <cr>          <Plug>(ghd-action)
  nmap <silent> <buffer> o             <Plug>(ghd-action)
  nmap <silent> <buffer> <2-LeftMouse> <Plug>(ghd-action)
  nmap <silent> <buffer> <c-n>         <Plug>(ghd-next)
  nmap <silent> <buffer> <c-p>         <Plug>(ghd-prev)
  nmap <silent> <buffer> C             <Plug>(ghd-clone)
endfunction

function! s:find_url()
  let line = getline(line('.'))
  let nth   = 0
  let start = 0
  let col   = col('.') - 1
  while 1
    let idx = match(line, '\[.\{-}\]', start)
    if idx == -1 || idx > col | return '' | endif

    let eidx = match(line, '\[.\{-}\zs\]', start)
    if col >= idx && col <= eidx && has_key(b:github_links, line('.'))
      return get(b:github_links[line('.')], nth, '')
    endif

    let start = eidx + 1
    let nth   = nth + 1
  endwhile
  return ''
endfunction

function! s:open_url(url)
  let cmd = s:option('open_command', '')
  if empty(cmd)
    if s:is_mac
      let cmd = 'open'
    elseif s:is_win
      execute ':silent !start rundll32 url.dll,FileProtocolHandler'
            \ shellescape(fnameescape(a:url))
      return
    elseif executable('xdg-open')
      let cmd = 'xdg-open'
    else
      echo "Cannot determine command to open: ". a:url
      return
    endif
    silent! call system(cmd . ' ' . shellescape(a:url))
    return
  endif
  execute ':silent !' . cmd . ' ' . shellescape(fnameescape(a:url))
  redraw!
endfunction

function! github_repos#status()
  if exists('b:github_statusline')
    let [type, what] = b:github_statusline
    return { 'type': type, 'what': what, 'url': s:find_url() }
  else
    return {}
  end
endfunction

function! github_repos#statusline()
  if exists('b:github_statusline')
    let prefix = '[GitHub '.join(b:github_statusline, ': ').']'
    let url = s:find_url()
    if empty(url)
      return prefix
    else
      return prefix .' '. url
    endif
  endif
  return s:original_statusline
endfunction

function! github_repos#autocomplete(arg, cmd, cur)
  let type = (a:cmd =~ '^GHSt') ? 'starred' : 'search'
  return filter(keys(s:history[type]), 'v:val =~ "^'. escape(a:arg, '"') .'"')
endfunction

function! s:action()
  let line = getline(line('.'))
  if line == s:more_line
    try
      call s:call_ruby('Loading ...')
    catch /^Vim:Interrupt$/
      let b:github_error = 1
    endtry

    if b:github_error
      call setline(line('$'), s:more_line)
      setlocal nomodifiable
    endif
    return
  endif

  let url = s:find_url()
  if !empty(url)
    call s:open_url(url)
  endif
endfunction

function! s:next_item(flags)
  call search(
             \ '\(^ *-- \zsMORE\)\|' .
             \ '\(^ *\[\zs[0-9a-fA-F]\{4,}\]\)\|' .
             \ '\(^ *Edited \[\zs\)\|' .
             \ '\(\(^ \{0,2}[0-9].\{-}\)\@<=\[\zs\)', a:flags)
endfunction

function! s:clone()
  let url = s:find_url()
  if !empty(url)
    if input('Clone '.url.' (y/n)? ') =~ '\v[yY]'
      if executable('ghq')
        execute '!ghq get '.url
      elseif executable('git')
        if a:0
          let dest = a:1
        else
          call inputsave()
          let dest = input('Where to clone: ')
          call inputrestore()
        endif
        execute '!git clone '.url.' '.dest
      endif
    endif
  endif
endfunction

" {{{
ruby << EOF
require 'rubygems' rescue nil # 1.9.1
begin
  require 'json/pure'
rescue LoadError
  begin
    require 'json'
  rescue LoadError
    VIM::command("let s:not_loaded = 'JSON gem is not installed. try: sudo gem install json_pure'")
  end
end

require 'net/https'
require 'time'

module GitHubRepos
  class << self
    def fetch uri, username, password
      tried = false
      begin
        req = Net::HTTP::Get.new(uri.request_uri, 'User-Agent' => 'vim')
        req.basic_auth username, password unless password.empty?

        api_endpoint = URI(VIM::evaluate('b:github_api_endpoint'))
        http = Net::HTTP.new(api_endpoint.host, uri.port)
        http.use_ssl = api_endpoint.scheme == 'https'
        http.ca_file = ENV['SSL_CERT_FILE'] if ENV['SSL_CERT_FILE']
        ot = VIM::evaluate("s:option('api_open_timeout', 10)").to_i
        rt = VIM::evaluate("s:option('api_read_timeout', 20)").to_i
        http.open_timeout = ot
        http.read_timeout = rt

        http.request req
      rescue OpenSSL::SSL::SSLError
        unless tried
          # https://gist.github.com/pweldon/767249
          tried = true
          certpath = File.join(VIM::evaluate("s:basedir"), 'cacert.pem')
          unless File.exists?(certpath)
            File.open(certpath, 'w') { |f|
              Net::HTTP.start('curl.haxx.se', 80) do |http|
                http.open_timeout = ot
                http.read_timeout = rt
                res = http.get '/ca/cacert.pem'
                f << res.body
              end
            }
          end
          ENV['SSL_CERT_FILE'] = certpath
          retry
        end
        raise
      end
    end

    def more
      main = Thread.current
      watcher = Thread.new {
        while VIM::evaluate('getchar(1)')
          sleep 0.1
        end
        main.kill
      }
      overbose = $VERBOSE
      $VERBOSE = nil
      username = VIM::evaluate('b:github_username')
      password = VIM::evaluate('b:github_password')
      uri      = URI(VIM::evaluate('b:github_more_url'))
      prefix   = VIM::evaluate('b:github_web_endpoint')

      res = fetch uri, username, password
      if res.code !~ /^2/
        if %w[401 403].include? res.code
          # Invalidate credentials
          VIM::command(%[call s:forget_password(b:github_profile, b:github_username)])
          VIM::command(%[let b:github_username = ''])
          VIM::command(%[let b:github_password = ''])
        end
        error "#{JSON.parse(res.body)['message']} (#{res.code})"
        return
      end

      # Doesn't work on 1.8.7
      # more = res.header['Link'].scan(/(?<=<).*?(?=>; rel=\"next)/)[0]
      more = res.header['Link'] && res.header['Link'].scan(/<.*?; rel=\"next/)[0]
      more = more && more.split('>; rel')[0][1..-1]

      VIM::command(%[normal! G"_d$])
      if more
        VIM::command(%[let b:github_more_url = '#{more}'])
      else
        VIM::command(%[unlet b:github_more_url])
      end

      bfr = VIM::Buffer.current
      result = JSON.parse(res.body)
      (result.is_a?(Hash) ? result['items'] : result).each do |repo|
        VIM::command('let b:github_index = b:github_index + 1')
        index = VIM::evaluate('b:github_index')
        lines = process(prefix, repo, index)
        lines.each_with_index do |line, idx|
          line, *links = line
          links = links.map { |l| l.start_with?('/') ? prefix + l : l }

          if idx == 0
            bfr.append bfr.count - 1,
              "#{index.to_s.rjust(3)}) #{line} (#{format_time repo['updated_at']})"
          else
            bfr.append bfr.count - 1, VIM::evaluate('b:github_indent') + line
          end
          VIM::command(%[let b:github_links[#{bfr.count - 1}] = [#{links.map { |e| vstr e }.join(', ')}]])
        end
      end
      bfr[bfr.count] = (more && !result.empty?) ? VIM::evaluate('s:more_line') : ''
      VIM::command(%[normal! ^zz])
    rescue Exception => e
      error e
    ensure
      watcher && watcher.kill
      $VERBOSE = overbose
    end

  private
    def process endpoint, repo, idx
      who = repo['owner']['login']
      name = repo['name']
      star = repo['stargazers_count']
      fork = repo['fork']
      desc = repo['description']
      where  = repo['url']

      who_url  = "#{endpoint}/#{who}"
      repo_url = "#{endpoint}/#{who}/#{name}"

      [[ "[#{who}/#{name}](#{star}) #{desc}", repo_url ]]
    end

    def error e
      VIM::command(%[let b:github_error = 1])
      VIM::command(%[echoerr #{vstr e}])
    end

    def vstr s
      %["#{s.to_s.gsub '"', '\"'}"]
    end

    def format_time at
      time = Time.parse(at)
      diff = Time.now - time
      pdenom = 1
      [
        [60,           'second'],
        [60 * 60,      'minute'],
        [60 * 60 * 24, 'hour'  ],
        [nil, 'day']
      ].each do |pair|
        denom, unit = pair
        if denom.nil? || diff < denom
          t = diff.to_i / pdenom
          return "#{t} #{unit}#{t == 1 ? '' : 's'} ago"
        end
        pdenom = denom
      end
    end

    def to_utf8 str
      if str.respond_to?(:force_encoding)
        str.force_encoding('UTF-8')
      else
        str
      end
    end

    def emoji str
      str
    end
  end
end
EOF
" }}}

let &cpo = s:save_cpo
unlet s:save_cpo
