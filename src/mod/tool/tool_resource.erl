-module(tool_resource).
-export([init/1, to_html/2]).

-include_lib("webmachine/include/webmachine.hrl").

init([]) -> 
    
    {ok, undefined}.

to_html(ReqData, State) ->
    Domain = 
        case mochiweb_headers:get_value("Host", ReqData#wm_reqdata.req_headers) of
            undefined -> "sh.erl.pm";
            R -> R
        end,
    {ok, ApplicationName} = application:get_application(?MODULE),

    Now = util:unixtime(),

    HtmlData = [
        {application_name, ApplicationName}, 
        {now, Now},
		{client_ip, ReqData#wm_reqdata.peer},
        {domain, Domain}
    ],

    {ok, Html} = genfsm_tool_dtl:render(HtmlData),
    {Html, ReqData, State}.


