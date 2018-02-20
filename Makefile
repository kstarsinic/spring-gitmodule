ORG         = spring-projects
ORGS        = spring-projects
FLAGS				=

all: $(ORGS)

$(ORG):	$(ORG).json
	@echo "$(ORG):"
	@./gitTool.pl $(FLAGS) $(ORG).json

# XXX we can only do 100 at a time
$(ORG).json:
	curl https://api.github.com/orgs/$(ORG)/repos?per_page=1000

