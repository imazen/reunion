  $(function(){
    

    $('.overrides_input_system input').on("change paste", function() {
      var t = $(this);
      var parent = t.parent();
      var message = t.parent().find('.message');
      var icon = t.parent().find('.glyphicon');
      var oldVal = t.data('old-val');
      var currentVal = t.val();

      if(currentVal == oldVal) {
          return; //check to prevent multiple simultaneous triggers
      }
      t.data('old-val', currentVal);

      message.text("");

      parent.removeClass('has-succes');
      parent.addClass('has-warning');
      parent.removeClass('has-error');


      $.post("/overrides/" + t.data('id'), {key: t.data('key'), value: currentVal},"json").done(function(data){
        //message.text("")
        parent.removeClass('has-warning');
        //icon.removeClass('icon-spinner')
        if (data.normalized_value && t.val() == currentVal && data.normalized_value != currentVal){
          t.val(data.normalized_value);
          parent.addClass('has-error');
          //icon.addClass('glyphicon-warning-sign')
        }else{
          parent.addClass('has-success');
        }
        if (data.warning) message.text(data.warning);

    //{change_made: change_made, normalized_value: value, id: id, key: key }.to_json

      });

    });
  });