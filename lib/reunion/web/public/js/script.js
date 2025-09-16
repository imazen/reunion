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

      parent.removeClass('has-success');
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

  async function copyPlainText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      try {
        await navigator.clipboard.writeText(text);
        return;
      } catch {
        const item = new ClipboardItem({
          'text/plain': new Blob([text], { type: 'text/plain' })
        });
        await navigator.clipboard.write([item]);
        return;
      }
    }
    // Fallback
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    document.body.removeChild(ta);
  }
  
  async function handleCopyClick(e) {
    e.preventDefault(); // don’t navigate away
    const link = e.currentTarget;
    const url = link.getAttribute('href');
  
    try {
      const res = await fetch(url, { mode: 'cors', cache: 'no-store' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const text = await res.text();
      await copyPlainText(text);
  
      const original = link.textContent;
      link.textContent = 'Copied!';
      setTimeout(() => (link.textContent = original), 1500);
    } catch (err) {
      console.error(err);
      alert('Copy failed: ' + err.message);
    }
  }
  
  // Attach listeners to all matching <a>
  document.querySelectorAll('a.copy-remote-file')
    .forEach(a => {a.addEventListener('click', handleCopyClick); console.log("added listener");});
 
});