# Motherhubber

Motherhubber is a crappy little Ruby script I whipped up to migrate issues from a Jira installation to github issues. It doesn't have a million features in the world, but it nails the basics. Namely: It takes the ticket body and creates a new ticket, then it grabs all of the comments associated with that ticket and appends them, attributing users where it can. If the ticket is closed, it then closes the ticket. It could do a lot of things better, but it works for what I needed it to do.


## Dependencies

* [Nokogiri](https://github.com/tenderlove/nokogiri)
* [Octokit](https://github.com/pengwynn/octokit/)


## Use

* Go into the Jira Administration section and export an XML dump of your Jira instance
* Edit the motherhubber.rb file and change the config settings in the Config section. You may have to poke around in the jira dump for some of the params.
* Install the gems above:

<pre>
  gem install nokogiri
</pre>

<pre>
  gem install octokit
</pre>

* Run the script:

<pre>
  ruby motherhubber.rb
</pre>

There is a good chance that this won't work for you directly off the bat. But it's enough to get you started.
