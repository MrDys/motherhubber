require 'nokogiri'
require 'octokit'


class Importer


##############################
# Config
##############################

# dry run?
@@dry_run = true

# Look in the Jira XML and find the project number

@@jira_project = 12345

# Specify the path to the jira xml dump
@@jira_xml_path = ""

# Github login creds
@@github_login = "gh_user"
@@github_password = "gh_password"

# Specify the github project
@@github_project = "User/repo"

# Author mapping Hash to convert jira users to github users. All assignable users need to be declared here even if they don't have a github
# account. If they don't give them a github account of "".
@@authors = Hash["jirauser" => "gh_user"]

# Status mapping Hash to convert jira statuses to github opened/closed state. Will probably work, but double check with the xml dump.
@@statuses = {
  1 => "Open",
  4 => "Reopened",
  3 => "In Progress",
  5 => "Resolved",
  6 => "Closed",
}
@@closed_statuses = [5, 6]
@@special_statuses = [4]

##############################
# End Config
##############################

@client
@doc
@milestones

def initialize()

  # Log into Github
  @client = Octokit::Client.new(:login => @@github_login, :password => @@github_password)

  # Open the XML dump from JIRA
  jira_xml_file = File.open(@@jira_xml_path)
  @doc = Nokogiri::XML(jira_xml_file)

  @milestones = {}
end

def process_text(text)
  text = text.gsub(/\{\{(.+?)\}\}/m, "`\n\\1\n`")
  text = text.gsub(/\{code\}(.+?)\{code\}/m, "```\n\\1\n```")
  text = text.gsub(/\{noformat\}(.+?)\{noformat\}/m, "```\n\\1\n```")
end

def get_author_text(name)
  if @@authors[name]
    name = @@authors[name]
    return "[#{name}](https://github.com/#{name})"
  else
    return name
  end
end


# create all of the milestones for the project
def create_milestones()
  created_milestones = {}
  open_milestones = @client.list_milestones(@@github_project, :state => "open")
  closed_milestones = @client.list_milestones(@@github_project, :state => "closed")

  all_milestones = []
  all_milestones.concat(open_milestones)
  all_milestones.concat(closed_milestones)

  # list all github milestones
  all_milestones.each do |milestone|
    created_milestones[milestone.title] = milestone.number
  end

  # create new milestones based on JIRA versions
  @doc.xpath("//Version[@project='#{@@jira_project}']").each do |version|
    id = version.xpath("@id").text.to_i
    name = version.xpath("@name").text
    description = version.xpath("@description").text

    released = version.xpath("@released")
    released = released ? released.text : ""
    released = released == "true"

    # check if already created
    if created_milestones[name]
      @milestones[id] = created_milestones[name]
      next
    end

    puts "creating milestone #{name}"

    milestone = @client.create_milestone(@@github_project, name, {
      :state => released ? "closed" : "open",
      :description => description
    })

    @milestones[id] = milestone.number
  end

  puts "Milestones:\n #{@milestones}\n\n"
end

def get_issue_type_name(issue)
  issue_type = issue.xpath("@type").text
  type_name = @doc.xpath("//IssueType[@id='#{issue_type}']")[0].xpath("@name").text
  return type_name
end

def get_gh_label(label)
  begin
    gh_label = @client.label(@@github_project, label)
  rescue Octokit::NotFound => e
    color = "%06x" % (rand * 0xffffff)
    gh_label = @client.add_label(@@github_project, label, color)
  end

  return gh_label.name
end

# Get only the issues from the specified project
def process_issues()
  issues = @doc.xpath("//Issue[@project='#{@@jira_project}']")

  issues.each do |issue|

    title = "#{issue.xpath("@key").text}: #{issue.xpath("@summary").text}"

    # Grab the body of jira ticket
    body = issue.xpath("@description").text + issue.xpath("description").text
    body = process_text(body)

    # Github does not allow you to assign a reporter via the API, so...
    # Add the original reporter as an addendum.
    body += "\n\n--------------------------------------------------"
    body += "\nImported from JIRA"

    reporter = issue.xpath("@reporter").text
    body += "\nOriginally reported by: #{get_author_text(reporter)}"

    options = {}

    # Grab the assignee of the jira ticket
    assign = @@authors[issues[0].xpath("@assignee").text] || issues[0].xpath("@assignee").text

    # versions / milestones
    issue_milestones = []

    @doc.xpath("//NodeAssociation[
      @sourceNodeEntity='Issue' and
      @sinkNodeEntity='Version' and
      @associationType='IssueFixVersion' and
      @sourceNodeId='#{issue.xpath("@id")}'
    ]").each do |version|
      version_id = version.xpath("@sinkNodeId").text.to_i
      milestone_id = @milestones[version_id]
      issue_milestones.push(milestone_id)
    end

    puts "milestones : #{issue_milestones}" if @@dry_run

    if issue_milestones.size > 1
      options[:milestone] = issue_milestones[issue_milestones.size - 1]
    elsif issue_milestones.size == 1
      options[:milestone] = issue_milestones[0]
    end

    # labels
    labels = options[:labels] = []

    # make the issue type a label
    issue_type = get_gh_label(get_issue_type_name(issue))
    labels.push(issue_type)

    # if the status is special, include it as a label
    status_id = issue.xpath("@status").text.to_i

    if @@special_statuses.include?(status_id)
      status_label = get_gh_label(@@statuses[status_id])
      labels.push(status_label)
    end

    # TODO actual JIRA labels


    # If it's unassigned, don't try to assign it when you create the ticket
    if assign != ""
      options[:assignee] = assign
    end

    # Create the ticket
    created = @client.create_issue(@@github_project, title, body, options)

    # Pull all of the comments associated with this particular iss
    com = @doc.xpath("//Action[@type='comment'][@issue="+issue.xpath("@id").text+"]").each do |c|
      author = get_author_text(c.xpath("@author").text)
      body = "#{author} said:\n" + process_text(c.xpath("@body").text + c.xpath("body").text)
      @client.add_comment(@@github_project, created.number, body) unless @@dry_run
    end


    # If the ticket's closed, close it up
    if @@closed_statuses.include?(status_id)
      @client.close_issue(@@github_project, created.number) unless @@dry_run
    end


    # A little status message never harmed nobody
    puts "Added: " + issue.xpath("@key").text

  end
end

def import()
  create_milestones()
  process_issues()

  puts "Finished importing issues to #{@@github_project}!"
end

end # Importer class


Importer.new().import()