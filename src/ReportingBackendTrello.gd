extends BugReportingBackendFacade
class_name BugReportingBackendTrello

func add_platform_specific_dispatch_data(args : BugReportingTool.DispatchArgs, data :Dictionary):
	#make the screenshot the ticket cover and remove it as an additional attachment
	data["cover"] =args.attachments[0]
	args.attachments.remove_at(0)
	
	pass
