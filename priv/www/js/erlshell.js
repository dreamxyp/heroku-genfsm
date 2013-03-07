var ErlShell = {
    "status" : 1,                                       //ErlShell状态，1表示没启动，2已启动
    "pid" : undefined,                                  //ErlShell的进程标识     
    "timer" : undefined,                                //心跳包定时
    "interval" : 10,                                    //心跳包定时间隔
    "line_num" : 1,                                     //ErlShell的行数
    "process" : 0,                                      //0标识当前没请求要处理，1反之
    "url" : "http://" + Domain + "/erlshellaction/"     //POST请求的地址
};

//创建命令行
ErlShell.create_es_line = function(line_num) {
    var _html = "";
    _html += '<table class="es_line">';
    _html += '    <tr>';
    _html += '        <td class="es_num">' + line_num + '></td>';
    _html += '        <td class="es_str">';
    _html += '            <div id="es_command_line" contenteditable="true"></div>';
    _html += '        </td>';
    _html += '    </tr>';
    _html += '    <tr><td colspan="2" id="es_result_' + line_num + '"></td></tr>';
    _html += '</table>';
    $("#es_div").append(_html);
    $("#es_command_line").focus();
};

//绑定命令行事件
ErlShell.bind_es_command_line_keypress = function() {
    $("#es_command_line").bind("keypress", function(event) {
        var keycode = event.keyCode ? event.keyCode : event.which;
        if ( keycode == 13 )        //回车事件 
        {
            var erl_str = "", data = {};
            // 获取命令行里的 erlang 表达式字符串
            erl_str = $.trim($("#es_command_line").text());
            if ( erl_str )
            {
                data = { "action" : 3, "pid" : ErlShell.pid, "erl_str" : erl_str };
                $("#es_div").css({"background-color" : "#EDEDED"});
                $.post(ErlShell.url, data, function(rs) {
                    if ( parseInt(rs.action) == 3 )
                    {
                        $("#es_div").css({"background-color" : "#FFF"});
                        var es_result = "#es_result_" + ErlShell.line_num;
                        $(es_result).html(rs.value);
                        if ( rs.result == 1 )
                        {
                            ErlShell.reset_es_keypress();
                            ErlShell.line_num = rs.line_num;
                            ErlShell.create_es_line(ErlShell.line_num);
                            ErlShell.bind_es_command_line_keypress();
                        }
                        else if ( rs.result == 31 )         //进程异常关闭
                        {
                            ErlShell.erlshell_stop();
                            alert("进程异常已关闭，请重新启动 ErlShell！"); 
                        }
                    }
                }, "json");
            } 
            return false;
        }
    });
};

ErlShell.reset_es_keypress = function() {
    $('#es_command_line').unbind('keypress');
    $('#es_command_line').attr({"id" : "", "contenteditable" : "false"});
};

// ErlShell 的心跳包函数
ErlShell.erlshell_heart = function() {
    //ErlShell如果已经关闭，则关停定时器
    if ( ErlShell.status != 2 )
    {
        if ( ErlShell.timer )
        {
            clearTimeout(ErlShell.timer);
        }
        ErlShell.timer = undefined;
        return false;
    }
    var data = { "action" : 4, "pid" : ErlShell.pid };
    $.post(ErlShell.url, data, function(rs) {
        if ( rs.result == 41 )                      //进程异常关闭
        {
            ErlShell.erlshell_stop();
            alert("进程异常已关闭，请重新启动 ErlShell！"); 
        }
    }, "json");
};

//启动ErlShell
ErlShell.erlshell_init = function(rs) {
    ErlShell.pid = rs.pid;
    ErlShell.interval = rs.interval;
    ErlShell.line_num = rs.line_num;
    ErlShell.status = 2;
    ErlShell.process = 0,
    $("#es_div").html("");
    //创建命令行
    ErlShell.create_es_line(ErlShell.line_num);
    //绑定命令行事件
    ErlShell.bind_es_command_line_keypress();
    $("#es_div").css({"background-color" : "#FFF"});
    $("#erlshell_action").html("Stop");
    //开启 ErlShell 心跳包定时器
    ErlShell.timer = setInterval(ErlShell.erlshell_heart, ErlShell.interval * 1000);
    ErlShell.erlshell_heart();
    $(window).bind('beforeunload', function() {
        return "确定要退出 ErlShell ？";
    });
};

// 关闭ErlShell
ErlShell.erlshell_stop = function() {
    if ( ErlShell.timer )
    {
        clearTimeout(ErlShell.timer);
    }
    ErlShell.timer = undefined;
    ErlShell.pid = undefined;
    ErlShell.status = 1;
    $("#erlshell_action").html("Start");
    $("#es_div").css({"background-color" : "#EDEDED"});
    ErlShell.reset_es_keypress();
    $(window).unbind('beforeunload');
}

$("#erlshell_action").click(function() {
    if ( ErlShell.process == 1 ) {
        return false;
    }
    ErlShell.process = 1;
    var data = ErlShell.status == 1 ? { "action" : 1 } : { "action" : 2, "pid" : ErlShell.pid };
    $.post(ErlShell.url, data, function(rs) {
        if ( rs.result == 1 )
        {
            switch ( parseInt(rs.action, 10) )
            {
                //启动ErlShell
                case 1:
                    ErlShell.erlshell_init(rs);
                    break;
                //关闭ErlShell
                case 2:
                    ErlShell.erlshell_stop();
                    break;
                default:
                    alert("ActionCode " + rs.action);
                    break;
            }
        }
        ErlShell.process = 0
    }, "json");
});

