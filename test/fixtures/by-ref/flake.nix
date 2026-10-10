# Inputs that name GitHub and the registry. The tests always override them,
# so nothing here is fetched; a test that fails to match fails on the fetch.
{
  inputs = {
    leaf.url = "github:Example/Leaf/main";
    registered.url = "leaf";
  };
  outputs =
    {
      self,
      leaf,
      registered,
    }:
    {
      leafValue = leaf.testValue;
      registeredValue = registered.testValue;
    };
}
