function aws-work-login --description 'Cache work AWS creds in shell, prompt 1Password once'
    set -l vals (op run --env-file ~/.config/op/aws-work.env -- sh -c 'printf "%s\\n%s" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY"')
    or return 1
    if test (count $vals) -lt 2
        echo "aws-work-login: failed to read credentials" >&2
        return 1
    end
    set -e AWS_PROFILE AWS_DEFAULT_PROFILE
    set -gx AWS_ACCESS_KEY_ID $vals[1]
    set -gx AWS_SECRET_ACCESS_KEY $vals[2]
    set -gx AWS_REGION us-east-1
    echo "work AWS creds cached for this shell. Wrappers will skip 1Password until logout."
end
