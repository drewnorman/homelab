# The provider reads the Admin API key only from OPENAI_ADMIN_KEY. Do not add
# the key as a variable: variable values can be persisted in plans and state.
provider "openai" {}
