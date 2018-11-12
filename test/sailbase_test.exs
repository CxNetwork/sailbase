defmodule SailbaseTest do
  use ExUnit.Case
  doctest Sailbase

  test "greets the world" do
    assert Sailbase.hello() == :world
  end
end
