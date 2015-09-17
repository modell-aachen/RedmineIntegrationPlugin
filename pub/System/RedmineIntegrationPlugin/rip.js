// Helper

$(function() {

Array.prototype.sum = function (prop) {
    var total = 0
    for ( var i = 0, _len = this.length; i < _len; i++ ) {
        total += this[i][prop]
    }
    return total
}

var toHHMMSS = function (integer) {
    var sec_num = parseInt(integer, 10); // don't forget the second param
    var hours   = Math.floor(sec_num / 3600);
    var minutes = Math.floor((sec_num - (hours * 3600)) / 60);
    var seconds = sec_num - (hours * 3600) - (minutes * 60);

    if (hours   < 10) {hours   = "0"+hours;}
    if (minutes < 10) {minutes = "0"+minutes;}
    if (seconds < 10) {seconds = "0"+seconds;}
    return hours+':'+minutes+':'+seconds;
}

function formater(object) {

    if ($.isEmptyObject(object)) {
        return
    }
    
    var string = object.subject;
    var length = 60;
    var trimmedString = string.length > length ? string.substring(0, length - 3) + "..." : string.substring(0, length);
    object.ticket_verbose = object.tracker+" #"+object.issue_id+": "+trimmedString
    return  object.ticket_verbose
}


// Model and Storage

var storage = {}

var create_timer = function () {

    var object =  {}
    object.id = Math.round(Math.random() * 100000000);
    object.time_log = [];
    object.duration_total = 0;
    storage[object.id] = object;
    change_timer(object.id)

    // ToDo: make ajax request to server

    return object

};


var update_timer = function (id, object) {

    for (var attrname in storage) {
        storage[id][attrname] = object[attrname];
    }

    // ToDo: make ajax request to server

    };

var delete_timer = function (id) {

     delete storage[id];

     // ToDo: make ajax request to server
};


var stop_all = function () {

    for (var key in storage) {

        var object = storage[key]

        if (object.start) {
            var end = new Date().getTime()
            object.time_log.push({start: object.start, end: end, duration: end - object.start })
            object.duration_total = object.time_log.sum("duration")
            delete object.start

            // ToDo: make ajax request to server
        }
    }
}
    
var change_timer = function (id) {

    var object = storage[id];

    if (!object.start) {
        stop_all()
        object.start = new Date().getTime();

        // ToDo: make ajax request to server

    } else {
         stop_all()
    }

}


var send_to_redmine = function (id) {

    object = storage[id]

    if (object.start) {
            var end = new Date().getTime()
            object.time_log.push({start: object.start, end: end, duration: end - object.start })
            object.duration_total = object.time_log.sum("duration")
            delete object.start

            // ToDo: make ajax request to server
        }


    data_obj = {
        project_id: object.project_id,
        activity_id: object.activity_id,
        issue_id: object.issue_id,
        hours: (object.duration_total/1000/60/60),
        comment: object.comment
    };


    $.ajax({
        type: 'POST',
        url: (foswiki.preferences.SCRIPTURL+"/rest/RedmineIntegrationPlugin/add_time_entry"),
        data: JSON.stringify(data_obj),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        object_id: object.id,
        success: function(result){
            storage[this.object_id].in_redmine = true;
            repaint_row(this.object_id);

            }
    });



}


// GUI Helper

var build_row = function (object) {

    var table_row = ""
    table_row += "<tr id="+object.id+">";
    table_row += "<td class='ticket'>" + (object.ticket_verbose || "--") + "</td>";
    table_row += "<td class='activity'>" + (object.activity_name || "--") + "</td>";
    table_row += "<td class='comment'>" + (object.comment || "--") + "</td>";
    table_row += "<td class='time_spent'>" + toHHMMSS(object.duration_total/1000) + "</td>";
    table_row += "<td class='notes'>" + (object.notes || "--") + "</td>";
    table_row += "<td class='tools'>";
    table_row += "<button type='button' class='change_timer'>Start</button>";
    table_row += "<button type='button' class='edit_timer'>Edit</button>";
    table_row += "<button type='button' class='send_timer'>Send</button>";
    table_row += "</td>";
    table_row += "</tr>";
    return table_row;
}




// GUI Functions


var gui_add_row = function (object) {
    $('#time_tracker > tbody:last-child').append(build_row(object));
}

var update_timer_button = function() {


    for (var key in storage) {

        var object = storage[key]
        if (object.start) {
            var time = new Date().getTime() - object.start
            $("tr#"+object.id).find('button.change_timer').text(toHHMMSS(time/1000));
        } else {
            $("tr#"+object.id).find('button.change_timer').text("Start");
            $("tr#"+object.id).find("td.time_spent").text(toHHMMSS(object.duration_total/1000))

        }
    }
}

var gui_change_timer = function(event) {
    change_timer($(event.target).closest("tr").attr('id'))
    update_timer_button()
}

var save_task = function () {

    object = storage[$(input_id).val()]

    select2_data = $(input_ticket).select2('data')

    for (var attrname in select2_data) { object[attrname] = select2_data[attrname]; }
    object.activity_id = $(select_activity).val();
    object.activity_name = $(select_activity).find("option:selected").text();
    object.comment = $(input_comment).val()
    object.notes = $(input_notes).val()

    repaint_row(object.id)
    dialog.dialog( "close" );
}

var gui_edit_timer = function () {

    var object = storage[$(event.target).closest("tr").attr('id')]

    if (object.ticket_id) {
        $('#input_ticket').select2('data', object)
        $('#input_ticket').trigger("change");
    }
    $("#input_id").val(object.id);
    $("#input_comment").val(object.comment);
    $("#input_notes").val(object.notes);

    dialog.dialog( "open" );
}

var repaint_row = function (id) {
    object = storage[id]

    object.in_redmine

    row_selector = $("tr#"+object.id)

    if (object.in_redmine) {
        row_selector.css('text-decoration', 'line-through')
    }

    row_selector.find("td.ticket").text(object.ticket_verbose || "--")
    row_selector.find("td.activity").text(object.activity_name || "--")
    row_selector.find("td.comment").text(object.comment || "--")
    row_selector.find("td.time_spent").text(toHHMMSS(object.duration_total/1000))
    row_selector.find("td.notes").text(object.notes || "--")
    
}

var gui_send_timer = function() {

    var object = storage[$(event.target).closest("tr").attr('id')]
    send_to_redmine(object.id)
}


// GUI Handler and Initialization

    setInterval(update_timer_button, 1000 );
    $('body').on('click', 'button.change_timer', gui_change_timer);
    $('body').on('click', 'button.edit_timer', gui_edit_timer);
    $('body').on('click', 'button.send_timer', gui_send_timer);

$(".add_timer").click(function(e) {
    gui_add_row(create_timer());
})



$("#input_ticket").on("change", function(e) {
        var object =  $("#input_ticket").select2('data')

        $.ajax({
            type: 'GET',
            url: (foswiki.preferences.SCRIPTURL+"/rest/RedmineIntegrationPlugin/get_activitys"),
            data: { p: object.project_id },
            success: function(result){

                $('#select_activity').empty()

                $.each(result,function(i,o){
                    $('#select_activity').append($('<option>', {
                    value: o.id,
                    text: o.name
                }));
                });
                if (object.activity_id) {
                    $('#select_activity').val(object.activity_id);
                }
        }});
})



// ToDo: Get Timer from Server, Paint GUI

var dialog = $( "#tt_edit_dialog" ).dialog({
    autoOpen: false,
    width: 550,
    modal: true,
    buttons: {
        Save: save_task,
        Cancel: function() {dialog.dialog( "close" );},
    },
    close: function() {
        $("#add_time_tracker").trigger("reset");
        $("#input_ticket").select2('data', {});
        $('#select_activity').empty()
    }
});

form = dialog.find( "form" ).on( "submit", function( event ) {
  event.preventDefault();
  save_task();
});


$("#input_ticket").select2({
    width: "95%",
    minimumInputLength: 3,
    ajax: {
        url: (foswiki.preferences.SCRIPTURL+"/rest/RedmineIntegrationPlugin/search_issue"),
        dataType: 'json',
        delay: 250,
        data: function (term) {return {q: term};},
        results: function (data) { return { results: data }}
    },
    formatResult: formater,
    formatSelection: formater,
    id: "issue_id"
});

});