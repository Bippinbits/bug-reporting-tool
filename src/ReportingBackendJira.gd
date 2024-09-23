extends BugReportingBackendFacade
class_name BugReportingBackendJira



# Jira API base URL and credentials
const JIRA_BASE_URL = "https://FILL_ME.atlassian.net/"
const JIRA_PROJECT_KEY = "FILL_ME"
const JIRA_ISSUE_TYPE = "Task"
# You can generate the JIRA_AUTH like this: Marshalls.utf8_to_base64(JIRA_EMAIL + ":" + JIRA_API_TOKEN)
const JIRA_AUTH := "FILL_ME"

func add_platform_specific_dispatch_data(args : BugReportingTool.DispatchArgs, data :Dictionary):
	pass

func _get_auth_header() -> String:
	return "Authorization: Basic " + JIRA_AUTH

func dispatch_internal(args : BugReportingTool.DispatchArgs, data : Dictionary):
	var headers = [
		_get_auth_header(),
		"Content-Type: application/json"
	]
	
	var issue_data = {
		"fields": {
			"project": {"key": JIRA_PROJECT_KEY},
			"summary": data.name,
			"description": {
				"type": "doc",
				"version": 1,
				"content": [{
					"type": "paragraph",
					"content": [{"type": "text", "text": data.desc}]
				}]
			},
			"issuetype": {"name": JIRA_ISSUE_TYPE}
		}
	}
	
	var http_request = HTTPRequest.new()
	args.node.add_child(http_request)
	
	var json_output = JSON.stringify(issue_data)
	print(json_output)
	http_request.request(JIRA_BASE_URL + "rest/api/3/issue/", headers, HTTPClient.METHOD_POST,json_output)
	
	http_request.request_completed.connect(func(a,b,c,d): _on_issue_creation_completed(args,a,b,c,d))

# Handle issue creation response
func _on_issue_creation_completed(args : BugReportingTool.DispatchArgs, result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code != 201:
		args.callback.call("Ticket creation failed: " + str(response_code))
		return
		
	var json = JSON.new()
	var response = json.parse(body.get_string_from_utf8())
	if response != OK:
		args.callback.call("Invalid response format")
		return
	
	var issue_id = json.data["id"]
	
	upload_attachments(args, issue_id)

# Function to upload attachments (Placeholder for actual file upload)
func upload_attachments(args : BugReportingTool.DispatchArgs, issue_id: String) -> void:
	upload_attachment_recursive(args,issue_id,0)

func upload_attachment_recursive(args : BugReportingTool.DispatchArgs, issue_id: String, idx):
	if idx >= args.attachments.size():
		args.callback.call("Upload successful.")
		return
	
	var http_request = HTTPRequest.new()
	args.node.add_child(http_request)
	var attachment = args.attachments[idx]
	var headers = [
		_get_auth_header(),
		"X-Atlassian-Token: no-check",
		"Content-Type: multipart/form-data; boundary=" + POST_BOUNDARY
	]
	
	var form_body :PackedByteArray
	form_body += ("--" + POST_BOUNDARY + "\r\n").to_ascii_buffer()
	form_body += ('Content-Disposition: form-data; name="file"; filename="' + attachment.filename + '"\r\n').to_ascii_buffer()
	form_body += ("Content-Type: "+attachment.mimetype +"\r\n\r\n").to_ascii_buffer()
	form_body += attachment.data
	form_body += ("\r\n").to_ascii_buffer()
	form_body += ("--" + POST_BOUNDARY + "--\r\n").to_ascii_buffer()
	# Send the HTTP request with multipart/form-data
	http_request.request_raw(JIRA_BASE_URL + "rest/api/3/issue/" + issue_id + "/attachments", headers, HTTPClient.METHOD_POST, form_body)
			
	http_request.request_completed.connect(func(a,response_code,c,d):
		if response_code != 200:
			args.callback.call("Ticket created but uploading attachment %s and subsequent failed." %attachment.filename)
		else:
			upload_attachment_recursive(args,issue_id,idx+1)
		)
