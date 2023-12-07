var script = document.createElement('script');
script.src = 'jquery-3.7.1.min.js';
document.getElementsByTagName('head')[0].appendChild(script);

var dynamicInputs = document.getElementById("dynamicInputs");
dynamicInputs.innerHTML = '';

function handlePageLoad() {
	var livestreamValue = getLivestreamStatus(livestreamValue);
	/* getLivestreamURLdata(); */
	// Adding classes and attributes to the prepopulated 'static' buttons on the webUI
	const staticInputElements = document.querySelectorAll(".inputStaticButtons");
	staticInputElements.forEach(el => 
		el.addEventListener("click", sendPHPID, setButtonActiveStyle, true));
	// Apply event listener to Livestream toggle
	$("#lstoggleinput").change
		(function() {
			if ($(this).is(':checked')) {
						$.ajax({
							type: "POST",
							url: "/enable_livestream.php",
							data: {
								lsonoff: "1"
								},
							success: function(response){
							console.log(response);
							}
						});

				} else {
                                                $.ajax({
                                                        type: "POST",
                                                        url: "/enable_livestream.php",
                                                        data: {
                                                                lsonoff: "0"
                                                                },
                                                        success: function(response){
                                                        console.log(response);
                                                        }
                                                });

				}
	});
	

	// get dynamic devices from etcd, and call createNewButton function to generate them
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
    	});
}

function getLivestreamStatus(livestreamValue) {
	// this function gets the livestream status from etcd and sets the livestream toggle button on/off
	$.ajax({
		type: "POST",
		url: "get_livestream_status.php",
		dataType: "json",
		success: function(returned_data) {
		const livestreamValue = JSON.parse(returned_data);
			if (livestreamValue == "1" ) {
		        console.log ("Livestream value is 1, enabling toggle automatically.");
		        $("#lstoggleinput")[0].checked=true; // set HTML checkbox to checked
		        } else {
		        console.log ("Livestream value is NOT 1, disabling checkbox toggle.");
		        $("#lstoggleinput")[0].checked=false; // set HTML checkbox to unchecked
		        }
		}
	})
}


function createNewButton(key, value, keyFull) {
	var divEntry		=	document.createElement("Div");
	var dynamicButton 	= 	document.createElement("Button");
	var renameButton	=	document.createElement("Button");
	const text		=	document.createTextNode(key);
	const id		=	document.createTextNode(counter + 1);
	dynamicButton.id	=	counter;
	/* create a div container, where the button, relabel button and any other associated elements reside */
	dynamicInputs.appendChild(divEntry);
	divEntry.setAttribute("divDeviceHash", value);
	divEntry.setAttribute("data-fulltext", keyFull);
	divEntry.setAttribute("divDevID", dynamicButton.id);
	divEntry.classList.add("dynamicInputButtonDiv");
	console.log("dynamic video source div created for device hash: " + value);
	/* add rename button */
	function createRenameButton() {
		var $btn = $('<button/>', {
				type: 'button',
				text: 'Rename',
				class: 'renameButton clickableButton',
				id: 'btn_rename'
		}).click(relabelElement);
	return $btn;
	}
	$(divEntry).append(createRenameButton());
//	divEntry.appendChild(renameButton);
        /* create the button */
        dynamicButton.appendChild(text);
        dynamicButton.setAttribute("value", value);
        dynamicButton.setAttribute("type", "button");
        dynamicButton.setAttribute("data-fulltext", keyFull);
        dynamicButton.classList.add("clickableButton", "dynamicInputButton");
        dynamicButton.addEventListener("click", sendPHPID, setButtonActiveStyle(this, true));
        divEntry.appendChild(dynamicButton);
	/* set counter +1 for button ID */
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
	const selectedDivHash		=	$(this).parent().attr('divDeviceHash');
						console.log("the found hash is: " + selectedDivHash);
	const relabelTarget		=	$(this).parent().attr('divDevID');
						console.log("the found button ID is: " + relabelTarget);
	const oldGenText		=	$(this).parent().attr('data-fulltext');
	const newTextInput		=	prompt("Enter new text label for this device:");
        console.log("Device full label is:" + oldGenText);
	console.log("New input label is:" +newTextInput);
	if (newTextInput !== null && newTextInput !== "") {
		document.getElementById(relabelTarget).innerText = newTextInput;
		document.getElementById(relabelTarget).oldGenText = oldGenText;
		console.log("Button text successfully applied as:" + newTextInput);
		console.log("The originally generated device field from Wavelet was: " + oldGenText);
		console.log("The button must be activated for any changes to reflect on the video banner!");
		$.ajax({
                        type: "POST",
                        url: "/set_label.php",
                        data: {
                                value: selectedDivHash,
                                label: newTextInput,
				oldvl: oldGenText
                              },
                        success: function(response){
                                console.log(response);
                        }
                });
	} else {
		return;
	}
}


function setButtonActiveStyle(button) {
	$(this).removeClass('active');
        $(this).addClass('active');
}

function applyLivestreamSettings() {
        postValue = (this.value);
        var vlsurl = $("#lsurl").val();
        var vapikey = $("#lsapikey").val();
        $.ajax({
                type: "POST",
                url: "/apply_livestream.php",
                data: {
                        lsurl: vlsurl,
                        apikey: vapikey
                        },
                success: function(response){
                        console.log(response);
                        }
        });
}
