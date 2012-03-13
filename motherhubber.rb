require 'nokogiri'
require 'octokit'

##############################
# Config 
##############################

# Look in the Jira XML and find the project number

jiraproject = 10001

# Specify the path to the jira xml dump
xmlpath = "jiradump.xml"

# Github login creds
login = "githubuser"
password = "githubpassword"

# Specify the github project
githubproject = "user/repo"

# Author mapping Hash to convert jira users to github users. All assignable users need to be declared here even if they don't have a github
# account. If they don't give them a github account of "".
authors = Hash["jirauser" => "githubuser", "jirauser2" => "githubuser2"]

# Status mapping Hash to convert jira statuses to github opened/closed state. Will probably work, but double check with the xml dump.
status = Hash[1 => "open", 2 => "closed", 3 => "open", 4 => "open", 5 => "closed", 6 => "closed"]

##############################
# End Config 
##############################



# Log into Github

client = Octokit::Client.new(:login => login, :password => password)

# Open the XML dump from JIRA

f = File.open(xmlpath)

doc = Nokogiri::XML(f)

# Get only the issues from the specified project

iss = doc.xpath("//Issue[@project='#{jiraproject}']")

iss.each do |i|

  # Grab the body of jira ticket
  bdy = i.xpath("@key").text + ": " + i.xpath("@description").text + i.xpath("description").text
  
  # Grab the assignee of the jira ticket
  assign = (true && authors[iss[0].xpath("@assignee").text]) || iss[0].xpath("@assignee").text
  
  # Create the ticket
  # If it's unassigned, don't try to assign it when you create the ticket
  if assign == ""
    created = client.create_issue(githubproject, i.xpath("@summary").text, bdy)
  else
    created = client.create_issue(githubproject, i.xpath("@summary").text, bdy, :assignee => assign)    
  end
    
  # Github does not allow you to assign a reporter via the API, so...
  # Add the original reporter as the first comment0
  
  reporter = (true && authors[i.xpath("@reporter").text]) || i.xpath("@reporter").text
  client.add_comment(githubproject, created.number, "Original reporter: " + reporter)
  
  # Pull all of the comments associated with this particular issue
  
  com = doc.xpath("//Action[@type='comment'][@issue="+i.xpath("@id").text+"]").each do |c|
    author = (true && authors[c.xpath("@author").text]) || c.xpath("@author").text
    client.add_comment(githubproject, created.number, author + ":  " + c.xpath("@body").text + c.xpath("body").text)
  end
  
  
  # If the ticket's closed, close it up
  if status[i.xpath("@status").text.to_i] == "closed"
    client.close_issue(githubproject, created.number)
  end
  
  
  # A little status message never harmed nobody
  puts "Added: " + i.xpath("@key").text
  
end





