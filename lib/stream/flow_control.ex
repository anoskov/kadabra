defmodule Kadabra.Stream.FlowControl do
  @moduledoc false

  defstruct queue: [],
            window: 56_536,
            max_frame_size: 16_536,
            stream_id: nil

  alias Kadabra.Http2

  @type t :: %__MODULE__{
    max_frame_size: non_neg_integer,
    queue: [...],
    window: integer
  }

  @type sock :: {:sslsocket, any, pid | {any, any}}

  @type frame :: {:send, binary}

  @data 0x0

  @doc ~S"""
  Returns new `Kadabra.Stream.FlowControl` with given opts.

  ## Examples

      iex> new(stream_id: 1)
      %Kadabra.Stream.FlowControl{stream_id: 1}
  """
  def new(opts) do
    %__MODULE__{
      stream_id: opts[:stream_id],
      window: opts[:window] || 56_536
    }
  end

  @doc ~S"""
  Enqueues a sendable payload.

  ## Examples

      iex> add(%Kadabra.Stream.FlowControl{}, "test")
      %Kadabra.Stream.FlowControl{queue: [{:send, "test"}]}
  """
  @spec add(t, binary) :: t
  def add(flow_control, bin) do
    queue = flow_control.queue ++ [{:send, bin}]
    %{flow_control | queue: queue}
  end

  @doc ~S"""
  Processes sendable data in queue, if any present and window
  is positive.

  ## Examples

      iex> process(%Kadabra.Stream.FlowControl{queue: []}, self())
      %Kadabra.Stream.FlowControl{queue: []}

      iex> process(%Kadabra.Stream.FlowControl{queue: [{:send, "test"}],
      ...> window: -20}, self())
      %Kadabra.Stream.FlowControl{queue: [{:send, "test"}], window: -20}
  """
  @spec process(t, sock) :: t
  def process(%{queue: []} = flow_control, _sock) do
    flow_control
  end
  def process(%{window: window} = flow_control, _sock) when window <= 0 do
    flow_control
  end
  def process(%{queue: [{:send, bin} | rest],
                window: window,
                stream_id: stream_id} = flow_control, socket) do

    size = byte_size(bin)

    if size > window do
      {chunk, rem_bin} = :erlang.split_binary(bin, window)
      p = Http2.build_frame(@data, 0x0, stream_id, chunk)
      :ssl.send(socket, p)

      flow_control = %{flow_control |
        queue: [{:send, rem_bin} | rest],
        window: 0
      }
      process(flow_control, socket)
    else
      p = Http2.build_frame(@data, 0x1, stream_id, bin)
      :ssl.send(socket, p)

      flow_control = %{flow_control | queue: rest, window: window - size}
      process(flow_control, socket)
    end
  end

  @doc ~S"""
  Increments stream window by given increment.

  ## Examples

      iex> increment_window(%Kadabra.Stream.FlowControl{window: 0}, 736)
      %Kadabra.Stream.FlowControl{window: 736}
  """
  def increment_window(flow_control, amount) do
    %{flow_control | window: flow_control.window + amount}
  end
end