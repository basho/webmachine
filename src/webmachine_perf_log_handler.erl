%% Copyright (c) 2011-2014 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.

%% @doc Default performance log handler for webmachine

-module(webmachine_perf_log_handler).

-behaviour(gen_event).

%% gen_event callbacks
-export([init/1,
         handle_call/2,
         handle_event/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-include("webmachine_logger.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-record(state, {hourstamp, filename, handle}).

-define(FILENAME, "perf.log").

%% ===================================================================
%% gen_event callbacks
%% ===================================================================

%% @private
init([BaseDir]) ->
    {ok,_} = webmachine_log:defer_refresh(?MODULE),
    FileName = filename:join(BaseDir, ?FILENAME),
    {Handle, DateHour} = webmachine_log:log_open(FileName),
    {ok, #state{filename=FileName, handle=Handle, hourstamp=DateHour}}.

%% @private
handle_call({_Label, MRef, get_modules}, State) ->
    {ok, {MRef, [?MODULE]}, State};
handle_call({refresh, Time}, State) ->
    {ok, ok, webmachine_log:maybe_rotate(?MODULE, Time, State)};
handle_call(_Request, State) ->
    {ok, ok, State}.

%% @private
handle_event({log_access, LogData}, State) ->
    NewState = webmachine_log:maybe_rotate(?MODULE, os:timestamp(), State),
    Msg = format_req(LogData),
    _ = webmachine_log:log_write(NewState#state.handle, Msg),
    {ok, NewState};
handle_event(_Event, State) ->
    {ok, State}.

%% @private
handle_info(_Info, State) ->
    {ok, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ===================================================================
%% Internal functions
%% ===================================================================

format_req(#wm_log_data{resource_module=Mod,
                        start_time=StartTime,
                        method=Method,
                        peer=Peer,
                        path=Path,
                        version=Version,
                        response_code=ResponseCode,
                        response_length=ResponseLength,
                        end_time=EndTime,
                        finish_time=FinishTime}) ->
    Time = webmachine_log:fmtnow(),
    Status = case ResponseCode of
                 {Code, _ReasonPhrase} when is_integer(Code)  ->
                     integer_to_list(Code);
                 _ when is_integer(ResponseCode) ->
                     integer_to_list(ResponseCode);
                 _ ->
                     ResponseCode
             end,
    Length = integer_to_list(ResponseLength),
    TTPD = webmachine_util:now_diff_milliseconds(EndTime, StartTime),
    TTPS = webmachine_util:now_diff_milliseconds(FinishTime, EndTime),
    fmt_plog(Time, Peer, atom_to_list(Method), Path, Version,
             Status, Length, atom_to_list(Mod), integer_to_list(TTPD),
             integer_to_list(TTPS)).

fmt_plog(Time, Ip,  Method, Path, {VM,Vm}, Status, Length, Mod, TTPD, TTPS) ->
    [webmachine_log:fmt_ip(Ip), " - ", [$\s], Time, [$\s, $"], Method, " ", Path,
     " HTTP/", integer_to_list(VM), ".", integer_to_list(Vm), [$",$\s],
     Status, [$\s], Length, " " , Mod, " ", TTPD, " ", TTPS, $\n].
