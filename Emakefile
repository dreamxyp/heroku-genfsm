{
    [
        'src/*'
        , 'src/*/*'
        , 'src/*/*/*'
        , 'src/*/*/*/*'
    ],
    [
        {hipe, [o3]}
        %%,encrypt_debug_info
        , debug_info
        , {i, "include"}
        , {outdir, "./../quant_release/ebin"}
%%        , {parse_transform, lager_transform}
        , {d, enable_auth}
        , {d, enable_gm}
        , {d, enable_debug}
        , {d, enable_debug_data}
    ]
}.
{
    [
        'test/*'
        , 'test/*/*'
        , 'src/*/*/*'
        , 'src/*/*/*/*'
    ],
    [
        {hipe, [o3]}
        %%,encrypt_debug_info
        , debug_info
        , {i, "include"}
        , {outdir, "./../quant_release/test/ebin"}
%%        , {parse_transform, lager_transform}
        , {d, enable_auth}
        , {d, enable_gm}
        , {d, enable_debug}
        , {d, enable_debug_data}
    ]
}.