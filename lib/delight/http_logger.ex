defmodule Delight.HTTPLogger do
  @moduledoc """
  Logs every outgoing HTTP request performed through Finch, the adapter used by
  `Req`.

  https://hexdocs.pm/finch/Finch.Telemetry.html
  """

  require Logger

  @events [
    [:finch, :request, :stop],
    [:finch, :request, :exception]
  ]

  @doc """
  Attaches the logger to Finch's telemetry events.
  """
  @spec attach() :: :ok | {:error, :already_exists}
  def attach do
    :telemetry.attach_many(__MODULE__, @events, &__MODULE__.handle_event/4, :no_config)
  end

  @doc false
  def handle_event([:finch, :request, :stop], measurements, metadata, _config) do
    log(metadata.request, outcome(metadata.result), measurements.duration)
  end

  def handle_event([:finch, :request, :exception], measurements, metadata, _config) do
    log(metadata.request, "exception #{inspect(metadata.reason)}", measurements.duration)
  end

  defp outcome({:ok, %Finch.Response{status: status}}), do: status
  defp outcome({:ok, _streamed_acc}), do: "ok"
  defp outcome({:error, exception}), do: "error #{Exception.message(exception)}"

  defp log(request, outcome, duration) do
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    Logger.debug("#{request.method} #{url(request)} -> #{outcome} (#{duration_ms}ms)")
  end

  defp url(request) do
    %URI{
      scheme: request.scheme && to_string(request.scheme),
      host: request.host,
      port: request.port,
      path: request.path,
      query: request.query
    }
    |> URI.to_string()
  end
end
