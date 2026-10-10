# Fails when its outputs are evaluated, to test what an error names.
{
  inputs = { };
  outputs = { self }: throw "broken on purpose";
}
