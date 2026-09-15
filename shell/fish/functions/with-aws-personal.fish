function with-aws-personal --description 'Run command with personal AWS SSO profile'
    env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN -u AWS_PROFILE -u AWS_DEFAULT_PROFILE AWS_PROFILE=personal $argv
end
