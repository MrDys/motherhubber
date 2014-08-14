require 'nokogiri'
require 'octokit'

##############################
# Config 
##############################

# Look in the Jira XML and find the project number

jira_project = 10160

# Specify the path to the jira xml dump
jira_xml_path = "/Users/bfagin/Documents/Code Projects/github_issue_importer/JIRA-backup-20140814/entities.xml"

# Github login creds
github_login = "UnquietCode"
github_password = ""

# Specify the github project
github_project = "UnquietCode/flapi-issues3"

# Author mapping Hash to convert jira users to github users. All assignable users need to be declared here even if they don't have a github
# account. If they don't give them a github account of "".
$authors = Hash["uqcadmin" => "UnquietCode", "jirauser2" => "githubuser2"]

# Status mapping Hash to convert jira statuses to github opened/closed state. Will probably work, but double check with the xml dump.
statuses = {
  1 => "Open",
  4 => "Reopened",
  3 => "In Progress",
  5 => "Resolved",
  6 => "Closed",
  10000 => "Evaluation"
}
closed_statuses = [5, 6]

##############################
# End Config 
##############################



# Log into Github

client = Octokit::Client.new(:login => github_login, :password => github_password)

# Open the XML dump from JIRA

jira_xml_file = File.open(jira_xml_path)

doc = Nokogiri::XML(jira_xml_file)


def process_text(text)
  text = text.gsub(/\{\{(.+?)\}\}/m, "`\n\\1\n`")
  text = text.gsub(/\{code\}(.+?)\{code\}/m, "```\n\\1\n```")
  text = text.gsub(/\{noformat\}(.+?)\{noformat\}/m, "```\n\\1\n```")
end

def get_author_text(name)
  if $authors[name]
    name = $authors[name]
    return "[#{name}](https://github.com/#{name})"
  else
    return name
  end
end

# Get only the issues from the specified project

issues = doc.xpath("//Issue[@project='#{jira_project}']")

issues.each do |issue|

  title = "#{issue.xpath("@key").text}: #{issue.xpath("@summary").text}"

  # Grab the body of jira ticket
  body = issue.xpath("@description").text + issue.xpath("description").text
  body = process_text(body)

  # Github does not allow you to assign a reporter via the API, so...
  # Add the original reporter as an addendum.
  body += "\n\n--------------------------------------------------\n"

  reporter = issue.xpath("@reporter").text
  body += "Originally reported by: #{get_author_text(reporter)}"

  # Grab the assignee of the jira ticket
  assign = $authors[issues[0].xpath("@assignee").text] || issues[0].xpath("@assignee").text
  
  # Create the ticket
  # If it's unassigned, don't try to assign it when you create the ticket
  if assign == ""
    created = client.create_issue(github_project, title, body)
  else
    created = client.create_issue(github_project, title, body, :assignee => assign)
  end

  # Pull all of the comments associated with this particular iss
  com = doc.xpath("//Action[@type='comment'][@issue="+issue.xpath("@id").text+"]").each do |c|
    author = get_author_text(c.xpath("@author").text)
    body = "#{author} said:\n" + process_text(c.xpath("@body").text + c.xpath("body").text)
    client.add_comment(github_project, created.number, body)
  end
  
  
  # If the ticket's closed, close it up
  if closed_statuses.include?(issue.xpath("@status").text.to_i)
    client.close_issue(github_project, created.number)
  end
  
  
  # A little status message never harmed nobody
  puts "Added: " + issue.xpath("@key").text
  
end





