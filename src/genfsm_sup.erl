%% @author author <author@example.com>
%% @copyright YYYY author.

%% @doc Supervisor for the genfsm application.

-module(genfsm_sup).
-author('author <author@example.com>').

-behaviour(supervisor).

%% External exports
-export([start_link/0, upgrade/0]).

%% supervisor callbacks
-export([init/1]).


%% @spec start_link() -> ServerRet
%% @doc API for starting the supervisor.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @spec upgrade() -> ok
%% @doc Add processes if necessary.
upgrade() ->
    {ok, {_, Specs}} = init([]),

    Old = sets:from_list(
        [Name || {Name, _, _, _} <- supervisor:which_children(?MODULE)]),
    New = sets:from_list([Name || {Name, _, _, _, _, _} <- Specs]),
    Kill = sets:subtract(Old, New),

    sets:fold(fun
                  (Id, ok) ->
                      supervisor:terminate_child(?MODULE, Id),
                      supervisor:delete_child(?MODULE, Id),
                      ok
              end, ok, Kill),

    [supervisor:start_child(?MODULE, Spec) || Spec <- Specs],
    ok.

%% @spec init([]) -> SupervisorTree
%% @doc supervisor callback.
init([]) ->
    Ip =
        case os:getenv("WEBMACHINE_IP") of
            false -> "0.0.0.0";
            Any -> Any
        end,
    {ok, App} =
        case application:get_application(?MODULE) of
            {ok, App0} -> {ok, App0};
            _ -> {ok, genfsm}
        end,
    %io:format("App1: ~p~n", [App]),
    %io:format("App2: ~p~n", [priv_dir(App)]),
    {ok, Dispatch} = file:consult(filename:join([priv_dir(App), "dispatch.conf"])),
    Port =
        case os:getenv("PORT") of
            false ->
                case os:getenv("WEBMACHINE_PORT") of
                    false -> 8000;
                    AnyPort -> AnyPort
                end;
            AnyPort -> list_to_integer(AnyPort)
        end,
    WebConfig = [
        {ip, Ip},
        {port, Port},
        %{log_dir, "priv/log"},
        {dispatch, Dispatch}],
    Egeoip = {egeoip, {egeoip, start_link, [egeoip]}, permanent, 5000, worker, [egeoip]},
    Web = {webmachine_mochiweb,
        {webmachine_mochiweb, start, [WebConfig]},
        permanent, 5000, worker, [mochiweb_socket_server]},

    GenfsmServer = {genfsm_server,
        {genfsm_server, start_link, []},
        permanent, 5000, worker, [genfsm_server]},

    Processes = [Egeoip, Web, GenfsmServer],

    {ok, {{one_for_one, 10, 10}, Processes}}.

%%
%% @doc return the priv dir
priv_dir(Mod) ->
    case code:priv_dir(Mod) of
        {error, bad_name} ->
            Ebin = filename:dirname(code:which(Mod)),
            filename:join(filename:dirname(Ebin), "priv");
        PrivDir ->
            PrivDir
    end.
