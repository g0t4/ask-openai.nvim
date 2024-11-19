local function create_provider_for_func(get_bearer_token)
    return {
        get_bearer_token = get_bearer_token,
    }
end

return create_provider_for_func
