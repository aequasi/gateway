defmodule Voice.Application do
  use Application

  def start(_type, _args) do
    Voice.start_link()
  end
end
