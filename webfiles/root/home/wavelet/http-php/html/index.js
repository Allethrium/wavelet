var script = document.createElement('script');
script.src = 'jquery-3.7.1.min.js';
document.getElementsByTagName('head')[0].appendChild(script);

var dynamicInputs = document.getElementById("dynamicInputs");
dynamicInputs.innerHTML = '';



function handlePageLoad() {
	const staticInputElements = document.querySelectorAll(".inputStaticButtons");
	staticInputElements.forEach(el => 
		el.addEventListener("click", sendPHPID, setButtonActiveStyle, true));
	$.ajax({
		type: "POST",
		url: "get_inputs.php",
		dataType: "json",
		success: function(returned_data) {
			counter = 3;
	        	console.log("JSON data received:");
	        	console.log(returned_data);
			returned_data.forEach(item => {
	                                var key = item['key'];                                      // extract key
	                                var value = item['value'];                                  // extract value
					var keyFull = item['keyFull']; 
					createNewButton(key, value, keyFull);
	                                })
			}
    	})
}

function createNewButton(key, value, keyFull) {
	/* first we need to check if the button already exists in persistent storage. 
	 * If so, restore it, test it against etcd to ensure it's still there,  and do nothing.
	 * This way, previously set button labels are persistent across clients/browser refreshes, and need to be set only once.
	 * We need to test for dead devices so we don't get exponentially increasing labels!
	 */
	
	/* else, create a new button object */
	var button 		= 	document.createElement("Button");
	const text		=	document.createTextNode(key);
	const id		=	document.createTextNode(counter + 1);
	button.id		=	counter;
	button.appendChild(text);
	button.setAttribute("value", value);
        button.setAttribute("type", "button");
	button.setAttribute("data-fulltext", keyFull);
	button.classList.add("clickableButton", "dynamicInputButton");
	button.addEventListener("click", sendPHPID, setButtonActiveStyle, true);
	button.addEventListener("dblclick", relabelElement, true);
	dynamicInputs.appendChild(button);
	counter++;
}

function sendPHPID(event) {
	postValue = (this.value);
	postLabel = (this.innerText);
		$.ajax({
			type: "POST",
			url: "/hash_select.php",
			data: {
				value: postValue,
				label: postLabel
			      },
			success: function(response){
				console.log(response); 
			}
		});
}

function relabelElement() {
	selectedElement		= (this.button);
	buttonID		= (this.id);
	const hash		= (this.value);
	const oldGenText	= (document.getElementById(buttonID).getAttribute("data-fulltext"));
	const newTextInput = prompt("Enter new text for the 'id' button:");
	console.log("Button ID is:" +buttonID);
        console.log("Device full label is:" + oldGenText);
	console.log("New input label is:" +newTextInput);
	if (newTextInput !== null && newTextInput !== "") {
		document.getElementById(buttonID).innerText = newTextInput;
		document.getElementById(buttonID).oldGenText = oldGenText;
		console.log("Button text successfully applied as:" + newTextInput);
		console.log("The originally generated device field from Wavelet was: " + oldGenText);
		console.log("The button must be activated for any changes to reflect on the video banner!");
		$.ajax({
                        type: "POST",
                        url: "/set_label.php",
                        data: {
                                value: hash,
                                label: newTextInput,
				oldvl: oldGenText
                              },
                        success: function(response){
                                console.log(response);
                        }
                });
		/* little concerned about this:
		 * find + overwrite on an etcd key in a client side function could be used to inject goodness knows what
		 * so we need to sanitize the input data from the web form
		 * limit to hash value length? 
		 */
	} else {
		return;
	}
}

function setButtonActiveStyle() {
	name.style.color = "red";
}

function applyLivestreamSettings() {
/* Here we onClick POST livestream settings through to another dedicated PHP handler which updates the livestream URL and APIkey.  Read only by dedicated livestream box. 
 *
 * consider not exposing the livestream DIV at all, unless the livestream box is registered on wavelet?  Would require this to also become dynamic content.
 *
 * */	
        postValue = (this.value);
                $.ajax({
                        type: "POST",
                        url: "/apply_livestream.php",
                        data: {
                                lsurl: postLSURL,
                                apikey: postLSapiKey
                              },
                        success: function(response){
                                console.log(response);
                        }
                });

}
