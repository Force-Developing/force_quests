$(function () {
    function display(bool) {
        if (bool) {
            $("#container").show();
        } else {
            $("#container").hide();
        }
    }

    display(false)

    window.addEventListener('message', function(event) {
        var item = event.data;
        if (item.type === "ui") {
            if (item.status == true) {
                display(true)
            } else {
                display(false)
            }
        }
    })

    document.onkeyup = function (data) {
        if (data.which == 8 || data.which == 27) {
            $.post('http://force_quests/exit', JSON.stringify({}));
            return
        }
    };
    $("#deleiverCargo").click(function () {
        $.post('http://force_quests/deleiverCargo', JSON.stringify({}));
        return
    })
    $("#pickupBoxes").click(function () {
        $.post('http://force_quests/pickupBoxes', JSON.stringify({}));
        return
    })
    $("#trashCar").click(function () {
        $.post('http://force_quests/trashCar', JSON.stringify({}));
        return
    })
    $("#cleaning").click(function () {
        $.post('http://force_quests/cleaning', JSON.stringify({}));
        return
    })
})
