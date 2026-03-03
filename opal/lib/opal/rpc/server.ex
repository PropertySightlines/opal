defmodule Opal.RPC.Server do
  @moduledoc """
  JSON-RPC 2.0 server over stdio.

  Reads newline-delimited JSON from stdin, dispatches to Opal API functions,
  and writes responses to stdout.

  Uses IO.stream/2 for stdin which properly handles both TTY and pipe input.
  """

  use GenServer

  require Logger

  alias Opal.RPC

  # -- State --

  defstruct [:stdout_port, :buffer]

  @type t :: %__MODULE__{
          stdout_port: port(),
          buffer: String.t()
        }

  # -- GenServer callbacks --

  @impl true
  def init(_opts) do
    # Open stdout port for writing responses
    stdout = :erlang.open_port({:fd, 1, 1}, [:binary, :out])

    # Start stdin reader task using IO.stream which handles TTY properly
    parent = self()
    Task.start_link(fn -> stdin_reader_loop(parent) end)

    {:ok, %__MODULE__{stdout_port: stdout, buffer: ""}}
  end

  @impl true
  def handle_info({:stdout_data, data}, state) do
    :erlang.port_command(state.stdout_port, data)
    {:noreply, state}
  end

  def handle_info({:stdin_line, line}, state) do
    line = String.trim(line)
    if line != "" do
      handle_request(line, state)
    end
    {:noreply, state}
  end

  def handle_info(:stdin_eof, state) do
    Logger.info("stdin closed, shutting down")
    {:stop, :normal, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -- Request handling --

  defp handle_request(line, state) do
    case RPC.decode(line) do
      {:request, id, method, params} ->
        result = dispatch(method, params)
        send_response(id, result, state)

      {:error, :parse_error} ->
        send_error(nil, -32700, "Parse error", state)

      {:error, :invalid_request} ->
        send_error(nil, -32600, "Invalid request", state)

      _ ->
        :ok
    end
  end

  defp dispatch(method, params) do
    try do
      case do_dispatch(method, params) do
        {:ok, result} -> {:ok, result}
        {:error, code, message} -> {:error, code, message}
      end
    catch
      kind, reason ->
        msg = Exception.format_banner(kind, reason)
        Logger.error("RPC dispatch crashed: #{msg}")
        {:error, -32603, "Internal error", msg}
    end
  end

  defp do_dispatch("session/start", params) do
    opts = decode_session_opts(params || %{})
    
    with {:ok, resolved_opts} <- opts,
         {:ok, agent} <- Opal.start_session(resolved_opts) do
      info = Opal.get_info(agent)
      auth = Opal.Auth.probe()
      
      {:ok, %{
        session_id: info.session_id,
        session_dir: info.session_dir,
        context_files: info.context_files,
        available_skills: Enum.map(info.available_skills, & &1.name),
        mcp_servers: Enum.map(info.mcp_servers, & &1.name),
        node_name: Atom.to_string(Node.self()),
        auth: auth
      }}
    end
  end

  defp do_dispatch("agent/prompt", %{"session_id" => sid, "text" => text}) do
    case Opal.Agent.get_state(sid) do
      %{agent: agent} when not is_nil(agent) ->
        Opal.prompt(agent, text)
        {:ok, %{queued: true}}
      
      _ ->
        {:error, -32000, "Session not found"}
    end
  end

  defp do_dispatch("auth/status", _params) do
    auth = Opal.Auth.probe()
    {:ok, auth}
  end

  defp do_dispatch("auth/providers", _params) do
    {:ok, %{providers: Opal.Auth.api_key_providers_ready()}}
  end

  defp do_dispatch(method, _params) do
    Logger.warning("Unknown method: #{method}")
    {:error, -32601, "Method not found"}
  end

  defp send_response(id, result, state) do
    json = RPC.encode_response(id, result)
    send(self(), {:stdout_data, json <> "\n"})
  end

  defp send_error(id, code, message, state) do
    json = RPC.encode_error(id, code, message)
    send(self(), {:stdout_data, json <> "\n"})
  end

  # -- Session opts decoding --

  defp decode_session_opts(params) when is_map(params) do
    opts = %{
      working_dir: Map.get(params, "working_dir", File.cwd!())
    }
    
    opts = case Map.get(params, "model") do
      %{"id" => id} when is_binary(id) ->
        Map.put(opts, :model, Opal.Provider.Model.new(id))
      _ ->
        opts
    end
    
    opts = case Map.get(params, "system_prompt") do
      prompt when is_binary(prompt) -> Map.put(opts, :system_prompt, prompt)
      _ -> opts
    end
    
    {:ok, opts}
  end

  defp decode_session_opts(_), do: {:error, :invalid_params}

  # -- Stdin reader using IO.stream --

  defp stdin_reader_loop(parent) do
    # IO.stream handles both TTY and pipe input correctly
    stream = IO.stream(:stdio, :line)
    
    for line <- stream do
      send(parent, {:stdin_line, line})
    end
    
    send(parent, :stdin_eof)
  end
end
