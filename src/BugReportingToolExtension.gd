extends Object
class_name BugReportingToolExtension

static func collect_additional_attachments(arr : Array[BugReportingTool.Attachment]):
	#add project-specific attachments here
	#savefiles, meta-files etc
	pass

static func collect_additional_infos(arr : Array[String]):
	#add game-specific infos here
	#version, difficulty, mission,settings etc
	pass
