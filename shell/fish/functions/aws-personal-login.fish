function aws-personal-login --description 'SSO login once, prompt-free after until token expiry'
    set -e AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
    env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN -u AWS_PROFILE -u AWS_DEFAULT_PROFILE aws sso login --sso-session local
    or return 1
    env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN -u AWS_PROFILE -u AWS_DEFAULT_PROFILE aws sts get-caller-identity --profile personal
    or return 1
    set -gx AWS_PROFILE personal
    set -gx AWS_REGION us-east-1
    echo "personal SSO cached. Plain `aws` in this shell now uses profile personal. Wrappers stay prompt-free until token expiry."
end
