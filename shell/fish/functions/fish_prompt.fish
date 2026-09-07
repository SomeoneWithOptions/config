function fish_prompt
    set_color purple
    echo -n (whoami)" "
    
    set_color white
    # Show ~ for home directory, otherwise show current directory name
    if test (pwd) = $HOME
        echo -n "~ "
    else
        echo -n (basename (pwd))" "
    end
    
    set_color green
    # Only show git branch if we're in a git repository
    if git rev-parse --git-dir >/dev/null 2>&1
        echo -n (git rev-parse --abbrev-ref HEAD)" "
    end
    
    set_color white
    echo -n '$ '
    set_color normal
end
