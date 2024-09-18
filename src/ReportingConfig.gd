extends Resource
class_name BugReportingConfig

enum BackendType {Trello, Jira}

# The URL pointing to the webserver location where "proxy.php" from this
# repository is served.
@export var proxy_url :String = "https://proxy.example/proxy.php"
@export var backend : BackendType
@export var categories: Array[String]
