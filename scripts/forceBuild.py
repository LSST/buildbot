import mechanize

browser = mechanize.Browser()
browser.set_handle_robots(False)

# Open web page and look at contents
response = browser.open ("http://lsst-buildx.ncsa.illinois.edu:8010/builders/DM_stack")

# Provide authentication info on 'login' form
browser.select_form("login")
browser.form['username'] = "everyman"

# Do not be alarmed, following is well-known to allow user invoked builds 
# The operations allowed are restricted.
browser.form['passwd'] = 'noneed'

response = browser.submit()

# Submit forceBuild form; no need to enter params since defaults OK
browser.select_form("force_build")
response = browser.submit()

