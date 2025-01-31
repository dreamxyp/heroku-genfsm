%% @author Justin Sheehy <justin@basho.com>
%% @author Andy Gross <andy@basho.com>
%% @author Bryan Fink <bryan@basho.com>
%% @copyright 2007-2014 Basho Technologies
%%
%%    Licensed under the Apache License, Version 2.0 (the "License");
%%    you may not use this file except in compliance with the License.
%%    You may obtain a copy of the License at
%%
%%        http://www.apache.org/licenses/LICENSE-2.0
%%
%%    Unless required by applicable law or agreed to in writing, software
%%    distributed under the License is distributed on an "AS IS" BASIS,
%%    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%    See the License for the specific language governing permissions and
%%    limitations under the License.

%% @doc Decision core for webmachine

-module(webmachine_decision_core).
-author('Justin Sheehy <justin@basho.com>').
-author('Andy Gross <andy@basho.com>').
-author('Bryan Fink <bryan@basho.com>').
-export([handle_request/2]).
-include("webmachine_logger.hrl").
-include("wm_compat.hrl").

%% Suppress Erlang/OTP 21 warnings about the new method to retrieve
%% stacktraces.
-ifdef(OTP_RELEASE).
-compile({nowarn_deprecated_function, [{erlang, get_stacktrace, 0}]}).
-endif.

handle_request(Resource, ReqState) ->
    _ = [erase(X) || X <- [decision, code, req_body, bytes_written, tmp_reqstate]],
    put(resource, Resource),
    put(reqstate, ReqState),
    try
        d(v3b13)
    catch _C:_Reason:ST ->
            error_response(ST)
    end.

wrcall(X) ->
    RS0 = get(reqstate),
    Req = webmachine_request:new(RS0),
    {Response, RS1} = webmachine_request:call(X, Req),
    put(reqstate, RS1),
    Response.

resource_call(Fun) ->
    Resource = get(resource),
    {Reply, NewResource, NewRS} = webmachine_resource:do(Fun,get(),Resource),
    put(resource, NewResource),
    put(reqstate, NewRS),
    Reply.

get_header_val(H) -> wrcall({get_req_header, H}).

method() -> wrcall(method).

d(DecisionID) ->
    put(decision, DecisionID),
    log_decision(DecisionID),
    decision(DecisionID).

respond(Code) when is_integer(Code) ->
    respond({Code, undefined});
respond({_, _}=CodeAndPhrase) ->
    Resource = get(resource),
    EndTime = os:timestamp(),
    respond(CodeAndPhrase, Resource, EndTime).

respond({Code, _ReasonPhrase}=CodeAndPhrase, Resource, EndTime)
  when Code >= 400, Code < 600 ->
    error_response(CodeAndPhrase, Resource, EndTime);
respond({304, _ReasonPhrase}=CodeAndPhrase, Resource, EndTime) ->
    wrcall({remove_resp_header, "Content-Type"}),
    case resource_call(generate_etag) of
        undefined -> nop;
        ETag -> wrcall({set_resp_header, "ETag", webmachine_util:quoted_string(ETag)})
    end,
    case resource_call(expires) of
        undefined -> nop;
        Exp ->
            wrcall({set_resp_header, "Expires",
                    webmachine_util:rfc1123_date(Exp)})
    end,
    finish_response(CodeAndPhrase, Resource, EndTime);
respond(CodeAndPhrase, Resource, EndTime) ->
    finish_response(CodeAndPhrase, Resource, EndTime).

finish_response({Code, _}=CodeAndPhrase, Resource, EndTime) ->
    put(code, Code),
    wrcall({set_response_code, CodeAndPhrase}),
    resource_call(finish_request),
    wrcall({send_response, CodeAndPhrase}),
    RMod = wrcall({get_metadata, 'resource_module'}),
    Notes = wrcall(notes),
    LogData0 = wrcall(log_data),
    LogData = LogData0#wm_log_data{resource_module=RMod,
                                   end_time=EndTime,
                                   notes=Notes},
    spawn(fun() -> do_log(LogData) end),
    webmachine_resource:stop(Resource).

error_response(Reason) ->
    error_response(500, Reason).

error_response(Code, Reason) ->
    Resource = get(resource),
    EndTime = os:timestamp(),
    error_response({Code, undefined}, Reason, Resource, EndTime).

error_response({Code, _}=CodeAndPhrase, Resource, EndTime) ->
    error_response({Code, _}=CodeAndPhrase,
                   webmachine_error:reason(Code),
                   Resource,
                   EndTime).

error_response({Code, _}=CodeAndPhrase, Reason, Resource, EndTime) ->
    {ok, ErrorHandler} = application:get_env(webmachine, error_handler),
    {ErrorHTML, ReqState} = ErrorHandler:render_error(
                              Code, {webmachine_request,get(reqstate)}, Reason),
    put(reqstate, ReqState),
    wrcall({set_resp_body, encode_body(ErrorHTML)}),
    finish_response(CodeAndPhrase, Resource, EndTime).

decision_test(Test,TestVal,TrueFlow,FalseFlow) ->
    case Test of
        {error, Reason} -> error_response(Reason);
        {error, Reason0, Reason1} -> error_response({Reason0, Reason1});
        {halt, Code} -> respond(Code);
        TestVal -> decision_flow(TrueFlow, Test);
        _ -> decision_flow(FalseFlow, Test)
    end.

decision_test_fn({error, Reason}, _TestFn, _TrueFlow, _FalseFlow) ->
    error_response(Reason);
decision_test_fn({error, R0, R1}, _TestFn, _TrueFlow, _FalseFlow) ->
    error_response({R0, R1});
decision_test_fn({halt, Code}, _TestFn, _TrueFlow, _FalseFlow) ->
    respond(Code);
decision_test_fn(Test,TestFn,TrueFlow,FalseFlow) ->
    case TestFn(Test) of
        true -> decision_flow(TrueFlow, Test);
        false -> decision_flow(FalseFlow, Test)
    end.

decision_flow(X, TestResult) when is_integer(X) ->
    if X >= 500 -> error_response(X, TestResult);
       true -> respond(X)
    end;
decision_flow(X, _TestResult) when is_atom(X) -> d(X).

do_log(LogData) ->
    webmachine_log:log_access(LogData).

log_decision(DecisionID) ->
    Resource = get(resource),
    webmachine_resource:log_d(DecisionID, Resource).

%% "Service Available"
decision(v3b13) ->
    decision_test(resource_call(service_available), true, v3b12, 503);
%% "Known method?"
decision(v3b12) ->
    decision_test(lists:member(method(), resource_call(known_methods)),
                  true, v3b11, 501);
%% "URI too long?"
decision(v3b11) ->
    decision_test(resource_call(uri_too_long), true, 414, v3b10);
%% "Method allowed?"
decision(v3b10) ->
    Methods = resource_call(allowed_methods),
    case lists:member(method(), Methods) of
        true ->
            d(v3b9);
        false ->
            Allowed = [case is_atom(M) of
                           true -> atom_to_list(M);
                           false -> M
                       end || M <- Methods],
            wrcall({set_resp_headers, [{"Allow",
                   string:join(Allowed, ", ")}]}),
            respond(405)
    end;

%% "Content-MD5 present?"
decision(v3b9) ->
    decision_test(get_header_val("content-md5"), undefined, v3b9b, v3b9a);
%% "Content-MD5 valid?"
decision(v3b9a) ->
    case resource_call(validate_content_checksum) of
        {error, Reason} ->
            error_response(Reason);
        {halt, Code} ->
            respond(Code);
        not_validated ->
            Checksum = base64:decode(get_header_val("content-md5")),
            BodyHash = compute_body_md5(),
            case BodyHash =:= Checksum of
                true -> d(v3b9b);
                _ ->
                    respond(400)
            end;
        false ->
            respond(400);
        _ -> d(v3b9b)
    end;
%% "Malformed?"
decision(v3b9b) ->
    decision_test(resource_call(malformed_request), true, 400, v3b8);
%% "Authorized?"
decision(v3b8) ->
    case resource_call(is_authorized) of
        true -> d(v3b7);
        {error, Reason} ->
            error_response(Reason);
        {halt, Code}  ->
            respond(Code);
        AuthHead ->
            wrcall({set_resp_header, "WWW-Authenticate", AuthHead}),
            respond(401)
    end;
%% "Forbidden?"
decision(v3b7) ->
    decision_test(resource_call(forbidden), true, 403, v3b6);
%% "Okay Content-* Headers?"
decision(v3b6) ->
    decision_test(resource_call(valid_content_headers), true, v3b5, 501);
%% "Known Content-Type?"
decision(v3b5) ->
    decision_test(resource_call(known_content_type), true, v3b4, 415);
%% "Req Entity Too Large?"
decision(v3b4) ->
    decision_test(resource_call(valid_entity_length), true, v3b3, 413);
%% "OPTIONS?"
decision(v3b3) ->
    case method() of
        'OPTIONS' ->
            Hdrs = resource_call(options),
            wrcall({set_resp_headers, Hdrs}),
            respond(200);
        _ ->
            d(v3c3)
    end;
%% Accept exists?
decision(v3c3) ->
    PTypes = [Type || {Type,_Fun} <- resource_call(content_types_provided)],
    case get_header_val("accept") of
        undefined ->
            wrcall({set_metadata, 'content-type', hd(PTypes)}),
            d(v3d4);
        _ ->
            d(v3c4)
    end;
%% Acceptable media type available?
decision(v3c4) ->
    PTypes = [Type || {Type,_Fun} <- resource_call(content_types_provided)],
    AcceptHdr = get_header_val("accept"),
    case webmachine_util:choose_media_type(PTypes, AcceptHdr) of
        none ->
            respond(406);
        MType ->
            wrcall({set_metadata, 'content-type', MType}),
            d(v3d4)
    end;
%% Accept-Language exists?
decision(v3d4) ->
    decision_test(get_header_val("accept-language"),
                  undefined, v3e5, v3d5);
%% Acceptable Language available? %% WMACH-46 (do this as proper conneg)
decision(v3d5) ->
    decision_test(resource_call(language_available), true, v3e5, 406);
%% Accept-Charset exists?
decision(v3e5) ->
    case get_header_val("accept-charset") of
        undefined -> decision_test(choose_charset("*"),
                                   none, 406, v3f6);
        _ -> d(v3e6)
    end;
%% Acceptable Charset available?
decision(v3e6) ->
    decision_test(choose_charset(get_header_val("accept-charset")),
                  none, 406, v3f6);
%% Accept-Encoding exists?
% (also, set content-type header here, now that charset is chosen)
decision(v3f6) ->
    CType = wrcall({get_metadata, 'content-type'}),
    CSet = case wrcall({get_metadata, 'chosen-charset'}) of
               undefined -> "";
               CS -> "; charset=" ++ CS
           end,
    wrcall({set_resp_header, "Content-Type", CType ++ CSet}),
    case get_header_val("accept-encoding") of
        undefined ->
            decision_test(choose_encoding("identity;q=1.0,*;q=0.5"),
                          none, 406, v3g7);
        _ -> d(v3f7)
    end;
%% Acceptable encoding available?
decision(v3f7) ->
    decision_test(choose_encoding(get_header_val("accept-encoding")),
                  none, 406, v3g7);
%% "Resource exists?"
decision(v3g7) ->
    % this is the first place after all conneg, so set Vary here
    case variances() of
        [] -> nop;
        Variances ->
            wrcall({set_resp_header, "Vary", string:join(Variances, ", ")})
    end,
    decision_test(resource_call(resource_exists), true, v3g8, v3h7);
%% "If-Match exists?"
decision(v3g8) ->
    decision_test(get_header_val("if-match"), undefined, v3h10, v3g9);
%% "If-Match: * exists"
decision(v3g9) ->
    decision_test(get_header_val("if-match"), "*", v3h10, v3g11);
%% "ETag in If-Match"
decision(v3g11) ->
    ETags = webmachine_util:split_quoted_strings(get_header_val("if-match")),
    decision_test_fn(resource_call(generate_etag),
                     fun(ETag) -> lists:member(ETag, ETags) end,
                     v3h10, 412);
%% "If-Match exists"
%% (note: need to reflect this change at in next version of diagram)
decision(v3h7) ->
    decision_test(get_header_val("if-match"), undefined, v3i7, 412);
%% "If-unmodified-since exists?"
decision(v3h10) ->
    decision_test(get_header_val("if-unmodified-since"),undefined,v3i12,v3h11);
%% "I-UM-S is valid date?"
decision(v3h11) ->
    IUMSDate = get_header_val("if-unmodified-since"),
    decision_test(webmachine_util:convert_request_date(IUMSDate),
                  bad_date, v3i12, v3h12);
%% "Last-Modified > I-UM-S?"
decision(v3h12) ->
    ReqDate = get_header_val("if-unmodified-since"),
    ReqErlDate = webmachine_util:convert_request_date(ReqDate),
    ResErlDate = resource_call(last_modified),
    decision_test(ResErlDate > ReqErlDate,
                  true, 412, v3i12);
%% "Moved permanently? (apply PUT to different URI)"
decision(v3i4) ->
    case resource_call(moved_permanently) of
        {true, MovedURI} ->
            wrcall({set_resp_header, "Location", MovedURI}),
            respond(301);
        false ->
            d(v3p3);
        {error, Reason} ->
            error_response(Reason);
        {halt, Code} ->
            respond(Code)
    end;
%% PUT?
decision(v3i7) ->
    decision_test(method(), 'PUT', v3i4, v3k7);
%% "If-none-match exists?"
decision(v3i12) ->
    decision_test(get_header_val("if-none-match"), undefined, v3l13, v3i13);
%% "If-None-Match: * exists?"
decision(v3i13) ->
    decision_test(get_header_val("if-none-match"), "*", v3j18, v3k13);
%% GET or HEAD?
decision(v3j18) ->
    decision_test(lists:member(method(),['GET','HEAD']),
                  true, 304, 412);
%% "Moved permanently?"
decision(v3k5) ->
    case resource_call(moved_permanently) of
        {true, MovedURI} ->
            wrcall({set_resp_header, "Location", MovedURI}),
            respond(301);
        false ->
            d(v3l5);
        {error, Reason} ->
            error_response(Reason);
        {halt, Code} ->
            respond(Code)
    end;
%% "Previously existed?"
decision(v3k7) ->
    decision_test(resource_call(previously_existed), true, v3k5, v3l7);
%% "Etag in if-none-match?"
decision(v3k13) ->
    ETags = webmachine_util:split_quoted_strings(get_header_val("if-none-match")),
    decision_test_fn(resource_call(generate_etag),
                     %% Membership test is a little counter-intuitive here; if the
                     %% provided ETag is a member, we follow the error case out
                     %% via v3j18.
                     fun(ETag) -> lists:member(ETag, ETags) end,
                     v3j18, v3l13);
%% "Moved temporarily?"
decision(v3l5) ->
    case resource_call(moved_temporarily) of
        {true, MovedURI} ->
            wrcall({set_resp_header, "Location", MovedURI}),
            respond(307);
        false ->
            d(v3m5);
        {error, Reason} ->
            error_response(Reason);
        {halt, Code} ->
            respond(Code)
    end;
%% "POST?"
decision(v3l7) ->
    decision_test(method(), 'POST', v3m7, 404);
%% "IMS exists?"
decision(v3l13) ->
    decision_test(get_header_val("if-modified-since"), undefined, v3m16, v3l14);
%% "IMS is valid date?"
decision(v3l14) ->
    IMSDate = get_header_val("if-modified-since"),
    decision_test(webmachine_util:convert_request_date(IMSDate),
                  bad_date, v3m16, v3l15);
%% "IMS > Now?"
decision(v3l15) ->
    NowDateTime = calendar:universal_time(),
    ReqDate = get_header_val("if-modified-since"),
    ReqErlDate = webmachine_util:convert_request_date(ReqDate),
    decision_test(ReqErlDate > NowDateTime,
                  true, v3m16, v3l17);
%% "Last-Modified > IMS?"
decision(v3l17) ->
    ReqDate = get_header_val("if-modified-since"),
    ReqErlDate = webmachine_util:convert_request_date(ReqDate),
    ResErlDate = resource_call(last_modified),
    decision_test(ResErlDate =:= undefined orelse ResErlDate > ReqErlDate,
                  true, v3m16, 304);
%% "POST?"
decision(v3m5) ->
    decision_test(method(), 'POST', v3n5, 410);
%% "Server allows POST to missing resource?"
decision(v3m7) ->
    decision_test(resource_call(allow_missing_post), true, v3n11, 404);
%% "DELETE?"
decision(v3m16) ->
    decision_test(method(), 'DELETE', v3m20, v3n16);
%% DELETE enacted immediately?
%% Also where DELETE is forced.
decision(v3m20) ->
    Result = resource_call(delete_resource),
    %% DELETE may have body and TCP connection will be closed unless body is read.
    %% See mochiweb_request:should_close.
    maybe_flush_body_stream(),
    decision_test(Result, true, v3m20b, 500);
decision(v3m20b) ->
    decision_test(resource_call(delete_completed), true, v3o20, 202);
%% "Server allows POST to missing resource?"
decision(v3n5) ->
    decision_test(resource_call(allow_missing_post), true, v3n11, 410);
%% "Redirect?"
decision(v3n11) ->
    Stage1 = case resource_call(post_is_create) of
        true ->
            case resource_call(create_path) of
                undefined -> error_response("post_is_create w/o create_path");
                NewPath ->
                    case is_list(NewPath) of
                        false -> error_response({"create_path not a string", NewPath});
                        true ->
                            BaseUri = case resource_call(base_uri) of
                                undefined -> wrcall(base_uri);
                                Any ->
                                    case [lists:last(Any)] of
                                        "/" -> lists:sublist(Any, erlang:length(Any) - 1);
                                        _ -> Any
                                    end
                            end,
                            FullPath = filename:join(["/", wrcall(path), NewPath]),
                            wrcall({set_disp_path, NewPath}),
                            case wrcall({get_resp_header, "Location"}) of
                                undefined -> wrcall({set_resp_header, "Location", BaseUri ++ FullPath});
                                _ -> ok
                            end,

                            Res = accept_helper(),
                            case Res of
                                {respond, Code} -> respond(Code);
                                {halt, Code} -> respond(Code);
                                {error, _,_} -> error_response(Res);
                                {error, _} -> error_response(Res);
                                _ -> stage1_ok
                            end
                    end
            end;
        _ ->
            case resource_call(process_post) of
                true ->
                    encode_body_if_set(),
                    stage1_ok;
                {halt, Code} -> respond(Code);
                Err -> error_response(Err)
            end
    end,
    case Stage1 of
        stage1_ok ->
            case wrcall(resp_redirect) of
                true ->
                    case wrcall({get_resp_header, "Location"}) of
                        undefined ->
                            Reason = "Response had do_redirect but no Location",
                            error_response(500, Reason);
                        _ ->
                            respond(303)
                    end;
                _ ->
                    d(v3p11)
            end;
        _ -> nop
    end;
%% "POST?"
decision(v3n16) ->
    decision_test(method(), 'POST', v3n11, v3o16);
%% Conflict?
decision(v3o14) ->
    case resource_call(is_conflict) of
        true -> respond(409);
        _ -> Res = accept_helper(),
             case Res of
                 {respond, Code} -> respond(Code);
                 {halt, Code} -> respond(Code);
                 {error, _,_} -> error_response(Res);
                 {error, _} -> error_response(Res);
                 _ -> d(v3p11)
             end
    end;
%% "PUT?"
decision(v3o16) ->
    decision_test(method(), 'PUT', v3o14, v3o18);
%% Multiple representations?
% (also where body generation for GET and HEAD is done)
decision(v3o18) ->
    BuildBody = case method() of
        'GET' -> true;
        'HEAD' -> true;
        _ -> false
    end,
    FinalBody = case BuildBody of
        true ->
            case resource_call(generate_etag) of
                undefined -> nop;
                ETag -> wrcall({set_resp_header, "ETag", webmachine_util:quoted_string(ETag)})
            end,
            CT = wrcall({get_metadata, 'content-type'}),
            case resource_call(last_modified) of
                undefined -> nop;
                LM ->
                    wrcall({set_resp_header, "Last-Modified",
                            webmachine_util:rfc1123_date(LM)})
            end,
            case resource_call(expires) of
                undefined -> nop;
                Exp ->
                    wrcall({set_resp_header, "Expires",
                            webmachine_util:rfc1123_date(Exp)})
            end,
            F = hd([Fun || {Type,Fun} <- resource_call(content_types_provided),
                           CT =:= webmachine_util:format_content_type(Type)]),
            resource_call(F);
        false -> nop
    end,
    case FinalBody of
        {error, _} -> error_response(FinalBody);
        {error, _,_} -> error_response(FinalBody);
        {halt, Code} -> respond(Code);
        nop -> d(v3o18b);
        _ -> wrcall({set_resp_body,
                     encode_body(FinalBody)}),
             d(v3o18b)
    end;

decision(v3o18b) ->
    decision_test(resource_call(multiple_choices), true, 300, 200);
%% Response includes an entity?
decision(v3o20) ->
    decision_test(wrcall(has_resp_body), true, v3o18, 204);
%% Conflict?
decision(v3p3) ->
    case resource_call(is_conflict) of
        true -> respond(409);
        _ -> Res = accept_helper(),
             case Res of
                 {respond, Code} -> respond(Code);
                 {halt, Code} -> respond(Code);
                 {error, _,_} -> error_response(Res);
                 {error, _} -> error_response(Res);
                 _ -> d(v3p11)
             end
    end;

%% New resource?  (at this point boils down to "has location header")
decision(v3p11) ->
    case wrcall({get_resp_header, "Location"}) of
        undefined -> d(v3o20);
        _ -> respond(201)
    end.

accept_helper() ->
    accept_helper(get_header_val("Content-Type")).

accept_helper(undefined) ->
    accept_helper("application/octet-stream");
accept_helper([]) ->
    accept_helper("application/octet-stream");
accept_helper(CT) ->
    {MT, MParams} = webmachine_util:media_type_to_detail(CT),
    wrcall({set_metadata, 'mediaparams', MParams}),
    case [Fun || {Type,Fun} <-
                     resource_call(content_types_accepted), MT =:= Type] of
        [] -> {respond,415};
        AcceptedContentList ->
            F = hd(AcceptedContentList),
            case resource_call(F) of
                true ->
                    encode_body_if_set(),
                    true;
                Result -> Result
            end
    end.

encode_body_if_set() ->
    case wrcall(has_resp_body) of
        true ->
            Body = wrcall(resp_body),
            wrcall({set_resp_body, encode_body(Body)}),
            true;
        _ -> false
    end.

encode_body(Body) ->
    ChosenCSet = wrcall({get_metadata, 'chosen-charset'}),
    Charsetter =
    case resource_call(charsets_provided) of
        no_charset -> fun(X) -> X end;
        CP ->
            case [Fun || {CSet,Fun} <- CP, ChosenCSet =:= CSet] of
                [] ->
                    fun(X) -> X end;
                [F | _] ->
                    F
            end
    end,
    ChosenEnc = wrcall({get_metadata, 'content-encoding'}),
    Encoder =
        case [Fun || {Enc,Fun} <- resource_call(encodings_provided),
                     ChosenEnc =:= Enc] of
            [] ->
                fun(X) -> X end;
            [E | _] ->
                E
        end,
    case Body of
        {stream, StreamBody} ->
            {stream, make_encoder_stream(Encoder, Charsetter, StreamBody)};
        {known_length_stream, 0, _StreamBody} ->
            {known_length_stream, 0, empty_stream()};
        {known_length_stream, Size, StreamBody} ->
            case method() of
                'HEAD' ->
                    {known_length_stream, Size, empty_stream()};
                _ ->
                    {known_length_stream, Size, make_encoder_stream(Encoder, Charsetter, StreamBody)}
            end;
        {stream, Size, Fun} ->
            {stream, Size, make_size_encoder_stream(Encoder, Charsetter, Fun)};
        {writer, BodyFun} ->
            {writer, {Encoder, Charsetter, BodyFun}};
        _ ->
            Encoder(Charsetter(iolist_to_binary(Body)))
    end.

%% @private
empty_stream() ->
    {<<>>, fun() -> {<<>>, done} end}.

make_encoder_stream(Encoder, Charsetter, {Body, done}) ->
    {Encoder(Charsetter(Body)), done};
make_encoder_stream(Encoder, Charsetter, {Body, Next}) ->
    {Encoder(Charsetter(Body)),
     fun() -> make_encoder_stream(Encoder, Charsetter, Next()) end}.

make_size_encoder_stream(Encoder, Charsetter, Fun) ->
    fun(Start, End) ->
            make_encoder_stream(Encoder, Charsetter, Fun(Start, End))
    end.

choose_encoding(AccEncHdr) ->
    Encs = [Enc || {Enc,_Fun} <- resource_call(encodings_provided)],
    case webmachine_util:choose_encoding(Encs, AccEncHdr) of
        none -> none;
        ChosenEnc ->
            case ChosenEnc of
                "identity" ->
                    nop;
                _ ->
                    wrcall({set_resp_header, "Content-Encoding",ChosenEnc})
            end,
            wrcall({set_metadata, 'content-encoding',ChosenEnc}),
            ChosenEnc
    end.

choose_charset(AccCharHdr) ->
    case resource_call(charsets_provided) of
        no_charset ->
            no_charset;
        CL ->
            CSets = [CSet || {CSet,_Fun} <- CL],
            case webmachine_util:choose_charset(CSets, AccCharHdr) of
                none -> none;
                Charset ->
                    wrcall({set_metadata, 'chosen-charset',Charset}),
                    Charset
            end
    end.

variances() ->
    Accept = case length(resource_call(content_types_provided)) of
        1 -> [];
        0 -> [];
        _ -> ["Accept"]
    end,
    AcceptEncoding = case length(resource_call(encodings_provided)) of
        1 -> [];
        0 -> [];
        _ -> ["Accept-Encoding"]
    end,
    AcceptCharset = case resource_call(charsets_provided) of
        no_charset -> [];
        CP ->
            case length(CP) of
                1 -> [];
                0 -> [];
                _ -> ["Accept-Charset"]
            end
    end,
    Accept ++ AcceptEncoding ++ AcceptCharset ++ resource_call(variances).

-ifndef(old_hash).
md5(Bin) ->
    crypto:hash(md5, Bin).

md5_init() ->
    crypto:hash_init(md5).

md5_update(Ctx, Bin) ->
    crypto:hash_update(Ctx, Bin).

md5_final(Ctx) ->
    crypto:hash_final(Ctx).
-else.
md5(Bin) ->
    crypto:md5(Bin).

md5_init() ->
    crypto:md5_init().

md5_update(Ctx, Bin) ->
    crypto:md5_update(Ctx, Bin).

md5_final(Ctx) ->
    crypto:md5_final(Ctx).
-endif.


compute_body_md5() ->
    case wrcall({req_body, 52428800}) of
        stream_conflict ->
            compute_body_md5_stream();
        Body ->
            md5(Body)
    end.

compute_body_md5_stream() ->
    MD5Ctx = md5_init(),
    compute_body_md5_stream(MD5Ctx, wrcall({stream_req_body, 8192}), <<>>).

compute_body_md5_stream(MD5, {Hunk, done}, Body) ->
    %% Save the body so it can be retrieved later
    put(reqstate, wrq:set_resp_body(Body, get(reqstate))),
    md5_final(md5_update(MD5, Hunk));
compute_body_md5_stream(MD5, {Hunk, Next}, Body) ->
    compute_body_md5_stream(md5_update(MD5, Hunk), Next(), <<Body/binary, Hunk/binary>>).

maybe_flush_body_stream() ->
    maybe_flush_body_stream(wrcall({stream_req_body, 8192})).

maybe_flush_body_stream(stream_conflict) ->
    ok;
maybe_flush_body_stream({_Hunk, done}) ->
    ok;
maybe_flush_body_stream({_Hunk, Next}) ->
    maybe_flush_body_stream(Next()).
