function aws-work --description 'AWS work 31533 via 1Password on demand'
    if set -q AWS_ACCESS_KEY_ID; and set -q AWS_SECRET_ACCESS_KEY
        env -u AWS_PROFILE -u AWS_DEFAULT_PROFILE aws $argv
    else
        env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN -u AWS_PROFILE -u AWS_DEFAULT_PROFILE op run --env-file ~/.config/op/aws-work.env -- aws $argv
    end
end
