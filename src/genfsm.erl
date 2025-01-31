%% @author author <author@example.com>
%% @copyright YYYY author.

%% @doc genfsm startup code

-module(genfsm).
-author('author <author@example.com>').
-export([start/0, start_link/0, stop/0]).

ensure_started(App) ->
    io:format("ensure_started: ~p~n", [App]),
    case application:start(App) of
        ok ->
            ok;
        {error, {already_started, App}} ->
            ok
    end.

%% @spec start_link() -> {ok,Pid::pid()}
%% @doc Starts the app for inclusion in a supervisor tree
start_link() ->
    ensure_started(inets),
    ensure_started(crypto),
    application:start(asn1),
    application:start(public_key),
    application:start(ssl),
    application:start(xmerl),
    application:start(compiler),
    application:start(syntax_tools),
    ensure_started(mochiweb),
    application:set_env(webmachine, webmachine_logger_module, 
                        webmachine_logger),
    ensure_started(webmachine),
    genfsm_sup:start_link(),
    ok.

%% @spec start() -> ok
%% @doc Start the genfsm server.
start() ->
    ensure_started(inets),
    ensure_started(crypto),
    application:start(asn1),
    application:start(public_key),
    application:start(ssl),
    application:start(xmerl),
    application:start(compiler),
    application:start(syntax_tools),
    ensure_started(mochiweb),
    application:set_env(webmachine, webmachine_logger_module,
                        webmachine_logger),
    ensure_started(webmachine),
    application:start(genfsm),
    ok.

%% @spec stop() -> ok
%% @doc Stop the genfsm server.
stop() ->
    Res = application:stop(genfsm),
    application:stop(webmachine),
    application:stop(mochiweb),
    application:start(syntax_tools),
    application:start(compiler),
    application:stop(xmerl),
    application:stop(ssl),
    application:stop(public_key),
    application:stop(crypto),
    application:stop(inets),
    Res.
