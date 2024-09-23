extends RefCounted
class_name BugReportingBackendFacade


# Internal constants, only change if you must ;-)
const POST_BOUNDARY: String = "GodotFileUploadBoundaryZ29kb3RmaWxl"
const URL_REGEX: String = \
	'^(?:(?<scheme>https?)://)?' + \
	'(?<host>\\[[a-fA-F0-9:.]+\\]|[^:/]+)' + \
	'(?::(?<port>[0-9]+))?(?<path>$|/.*)'


func create_post_data(key: String, value) -> PackedByteArray:
	var body: PackedByteArray = []
	var extra: String = ''
	var bytes: PackedByteArray = []

	if value is Array:
		for idx in range(0, value.size()):
			var newkey = "%s[%d]" % [key, idx]
			body += create_post_data(newkey, value[idx])
		return body
	elif value is BugReportingTool.Attachment:
		extra = '; filename="' + value.filename + '"'
		if value.mimetype != 'application/octet-stream':
			extra += '\r\nContent-Type: ' + value.mimetype
		bytes = value.data
	elif value != null:
		bytes = value.to_utf8_buffer()

	var buf = 'Content-Disposition: form-data; name="' + key + '"' + extra
	body += ('--' + POST_BOUNDARY + '\r\n' + buf + '\r\n\r\n').to_ascii_buffer()
	body += bytes + '\r\n'.to_ascii_buffer()
	return body

func send_post(_http: HTTPClient, path: String, data: Dictionary) -> int:
	var headers = [
		'Content-Type: multipart/form-data; boundary=' + POST_BOUNDARY,
	]

	var body: PackedByteArray = []
	for key in data:
		body += create_post_data(key, data[key])
	body += ('--' + POST_BOUNDARY + '--\r\n').to_ascii_buffer()

	return _http.request_raw(HTTPClient.METHOD_POST, path, headers, body)

func parse_url(url: String) -> Dictionary:
	var regex = RegEx.new()

	if regex.compile(URL_REGEX) != OK:
		return {}

	var re_match = regex.search(url)
	if re_match == null:
		return {}

	var scheme = re_match.get_string('scheme')
	if not scheme:
		scheme = 'http'

	var port: int = 80 if scheme == 'http' else 443
	if re_match.get_string('port'):
		port = int(re_match.get_string('port'))

	return {
		'scheme': scheme,
		'host': re_match.get_string('host'),
		'port': port,
		'path': re_match.get_string('path'),
	}
	
func add_platform_specific_dispatch_data(args : BugReportingTool.DispatchArgs, data :Dictionary):
	pass
	
func dispatch(args : BugReportingTool.DispatchArgs):
	var details: String = ""
	for s in args.details:
		details += s + "\n"
	var data = {
		'name': args.title + " #" + args.report_hash,
		'desc': ("\n\n**--------- MESSAGE --------**\n\n" + args.message + "\n\n\n\n**---------- REPORT ---------**\n\n" + details),
		"attachments": args.attachments
	}
	
	add_platform_specific_dispatch_data(args,data)
	dispatch_internal(args,data)

func dispatch_internal(args : BugReportingTool.DispatchArgs, data : Dictionary):
	var parsed_url = parse_url(args.config.proxy_url)
	if parsed_url.is_empty():
		args.callback.call("Wrong proxy URL provided, can't send data :-(")
		return
	
	var http = HTTPClient.new()
	var timer = Timer.new()
	timer.wait_time = 0.1
	args.node.add_child(timer)
	
	var err = http.connect_to_host(parsed_url["scheme"] + "://" +	parsed_url['host'])
	if err != OK:
		args.callback.call("Unable to connect to host :-( " +  str(err))
		return
	var timeout = 30.0
	timer.start()
	while http.get_status() in [
		HTTPClient.STATUS_CONNECTING,
		HTTPClient.STATUS_RESOLVING
	]:
		http.poll()
		await timer.timeout
		timeout -= timer.get_wait_time()
		if timeout < 0.0:
			args.callback.call("Timeout while waiting to connect to server :-(")
			timer.stop()
			return
	timer.stop()

	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		args.callback.call("Unable to connect to server :-( " +  str(http.get_status()))
		return

	if send_post(http, parsed_url['path'], data) != OK:
		args.callback.call("Unable to send feedback to server :-(")
		return

	timeout = 30.0
	timer.start()
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		await timer.timeout
		timeout -= timer.get_wait_time()
		if timeout < 0.0:
			args.callback.call("Timeout waiting for server acknowledgement :-(")
			timer.stop()
			return
	timer.stop()

	if not http.get_status() in [
		HTTPClient.STATUS_BODY,
		HTTPClient.STATUS_CONNECTED
	]:
		args.callback.call("Unable to connect to server :-(")
		return

	if http.has_response() && http.get_response_code() != 200:
		timeout = 30.0
		timer.start()
		var response: PackedByteArray = []
		while http.get_status() == HTTPClient.STATUS_BODY:
			http.poll()
			var chunk = http.read_response_body_chunk()
			if chunk.size() == 0:
				await timer.timeout
				timeout -= timer.get_wait_time()
				if timeout < 0.0:
					args.callback.call("Timeout waiting for server response :-(")
					timer.stop()
					return
			else:
				response += chunk
		timer.stop()
		args.callback.call('Error from server: ' + response.get_string_from_utf8())
		return

	args.callback.call("Feedback sent successfully, thank you!")
