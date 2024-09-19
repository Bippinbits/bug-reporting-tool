<?php declare(strict_types=1);

// Jira API base URL and credentials
const JIRA_BASE_URL = '@YOUR_JIRA_BASE_URL@';
const JIRA_EMAIL = '@YOUR_JIRA_EMAIL@';
const JIRA_API_TOKEN = '@YOUR_JIRA_API_TOKEN@';

// Jira project ID and issue type (e.g., Task, Bug)
const JIRA_PROJECT_KEY = '@YOUR_JIRA_PROJECT_KEY@';
const JIRA_ISSUE_TYPE = 'Task'; // Change as per your requirement

/**
 * Function to convert a file upload into a CURLFile for Jira.
 */
function upload2curl(array &$file): CURLFile {
    if ($file['error'] !== UPLOAD_ERR_OK) {
        http_response_code(400);
        exit('Upload of attachment '.$file['name'].' failed');
    }

    if (!is_uploaded_file($file['tmp_name'])) {
        http_response_code(400);
        exit('Refused possible file upload attack for '.$file['name']);
    }

    $filetype = mime_content_type($file['tmp_name']);
    $suffix = pathinfo($file['name'], PATHINFO_EXTENSION) ?? null;

    $name = $file['name'];
    if (!preg_match('/^[a-zA-Z0-9][a-zA-Z0-9_-]*\\.[a-zA-Z0-9]+$/', $name)) {
        $name = uniqid().($suffix !== null ? '.'.$suffix : '');
    }

    return curl_file_create($file['tmp_name'], $filetype, $name);
}

// Validate POST data
if (empty($_POST['name']) || empty($_POST['desc'])) {
    http_response_code(400);
    exit('Insufficient data');
}

// Set up the basic authentication header for Jira
$auth = base64_encode(JIRA_EMAIL.':'.JIRA_API_TOKEN);
$headers = [
    'Authorization: Basic '.$auth,
    'Content-Type: application/json'
];

// Prepare the issue creation payload using ADF format for the description
$issue_data = [
    'fields' => [
        'project' => [
            'key' => JIRA_PROJECT_KEY
        ],
        'summary' => $_POST['name'],
        'description' => [
            'type' => 'doc',
            'version' => 1,
            'content' => [
                [
                    'type' => 'paragraph',
                    'content' => [
                        [
                            'type' => 'text',
                            'text' => $_POST['desc']
                        ]
                    ]
                ]
            ]
        ],
        'issuetype' => [
            'name' => JIRA_ISSUE_TYPE
        ]
    ]
];
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, JIRA_BASE_URL.'/rest/api/3/issue/');
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($issue_data));

// Execute the issue creation request
$issue_response = curl_exec($ch);
if ($issue_response === false) {
    http_response_code(502);
    curl_close($ch);
    exit('Unable to create issue');
}

$issue = json_decode($issue_response, true);
if ($issue === null || !array_key_exists('id', $issue)) {
    http_response_code(502);
    curl_close($ch);
    exit('Unable to find issue identifier');
}

$issue_id = $issue['id'];

// Upload attachments
if (is_array($_FILES['attachments'] ?? null)) {
    foreach ($_FILES['attachments']['name'] as $index => $name) {
        $file = [
            'name' => $name,
            'type' => $_FILES['attachments']['type'][$index],
            'error' => $_FILES['attachments']['error'][$index],
            'tmp_name' => $_FILES['attachments']['tmp_name'][$index]
        ];

        $attachment = upload2curl($file);

        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, JIRA_BASE_URL.'/rest/api/3/issue/'.$issue_id.'/attachments');
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Authorization: Basic '.$auth,
            'X-Atlassian-Token: no-check'
        ]);
        curl_setopt($ch, CURLOPT_POSTFIELDS, ['file' => $attachment]);
        
        $response = curl_exec($ch);
        if ($response === false) {
            http_response_code(502);
            curl_close($ch);
            exit('Unable to upload attachment ' . ($index + 1) . ' to issue');
        }

        // Optionally check for response status to ensure upload success
        $response_info = curl_getinfo($ch);
        if ($response_info['http_code'] !== 200) {
            http_response_code(502);
            curl_close($ch);
            exit('Attachment upload failed with response: ' . $response);
        }

        curl_close($ch);
    }
}

http_response_code(200);
exit('OK');