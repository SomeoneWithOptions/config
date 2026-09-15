alias oq='omarchy-qemu'
alias t='terraform'
set -g fish_greeting ""

if command -q mise
    mise activate fish | source
end

# xAI Grok on Vertex via service-account JSON, no gcloud login needed.
set -gx GOOGLE_APPLICATION_CREDENTIALS /home/andres/it-tools-4fc1b6dd-9f8e204c0503.json
set -gx XAI_VERTEX_PROJECT_ID it-tools-4fc1b6dd

function aws-work --description 'AWS work 31533 via 1Password on demand'
    env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN -u AWS_PROFILE -u AWS_DEFAULT_PROFILE op run --env-file ~/.config/op/aws-work.env -- aws $argv
end

function with-aws-work --description 'Run command with work AWS credentials from 1Password'
    env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN -u AWS_PROFILE -u AWS_DEFAULT_PROFILE op run --env-file ~/.config/op/aws-work.env -- $argv
end

function aws-personal --description 'AWS personal via IAM Identity Center'
    env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN -u AWS_PROFILE -u AWS_DEFAULT_PROFILE aws --profile personal $argv
end

function with-aws-personal --description 'Run command with personal AWS SSO profile'
    env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN -u AWS_PROFILE -u AWS_DEFAULT_PROFILE AWS_PROFILE=personal $argv
end
