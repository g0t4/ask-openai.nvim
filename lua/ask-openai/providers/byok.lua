local function create_provider_for_func(get_bearer_token)
    return {
        get_bearer_token = get_bearer_token,
    }
end

-- FYI yes this looks silly but wrapping the func in a module (like other providers) means some providers can have more behavior than the one function (i.e. copilot)
return create_provider_for_func
