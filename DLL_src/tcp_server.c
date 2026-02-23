/*
 * tcp_server.c
 * Copy Trading TCP System — Minimal TCP server DLL for MQL5
 *
 * Provides bind/listen/accept functionality that MQL5 cannot do natively.
 * Compiled as a 64-bit Windows DLL and placed in MT5's MQL5/Libraries/ folder.
 *
 * COMPILE (MSVC x64 Developer Command Prompt):
 *   cl /LD /O2 /W3 tcp_server.c ws2_32.lib /Fe:tcp_server.dll
 *
 * COMPILE (MinGW-w64, 64-bit):
 *   x86_64-w64-mingw32-gcc -shared -O2 -o tcp_server.dll tcp_server.c -lws2_32
 *
 * Place tcp_server.dll in:
 *   C:\Users\<user>\AppData\Roaming\MetaQuotes\Terminal\<id>\MQL5\Libraries\
 *
 * MT5 must have "Allow DLL imports" enabled in Tools → Options → Expert Advisors.
 */

#include <winsock2.h>
#include <windows.h>

#pragma comment(lib, "ws2_32.lib")

#define MAX_CLIENTS 8

static SOCKET g_server   = INVALID_SOCKET;
static SOCKET g_clients[MAX_CLIENTS];
static int    g_client_count = 0;
static int    g_initialized  = 0;

/* ------------------------------------------------------------------ */
/* DllMain — init client array on attach                               */
/* ------------------------------------------------------------------ */
BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved)
{
    switch(fdwReason)
    {
        case DLL_PROCESS_ATTACH:
            for(int i = 0; i < MAX_CLIENTS; i++)
                g_clients[i] = INVALID_SOCKET;
            break;
        case DLL_PROCESS_DETACH:
            /* lpvReserved==NULL means FreeLibrary path (safe to cleanup).
             * lpvReserved!=NULL means process termination — avoid Winsock calls
             * under loader lock to prevent deadlocks. */
            if(g_initialized && lpvReserved == NULL) ServerClose();
            break;
    }
    return TRUE;
}

/* ------------------------------------------------------------------ */
/* ServerCreate(port)                                                  */
/* Returns: 0=success, -1=WSAStartup failed, -2=socket failed,       */
/*          -3=bind failed, -4=listen failed                           */
/* ------------------------------------------------------------------ */
__declspec(dllexport) int __stdcall ServerCreate(int port)
{
    WSADATA wsa;
    if(WSAStartup(MAKEWORD(2,2), &wsa) != 0)
        return -1;

    g_server = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if(g_server == INVALID_SOCKET)
    {
        WSACleanup();
        return -2;
    }

    /* Allow fast restart after crash */
    int opt = 1;
    setsockopt(g_server, SOL_SOCKET, SO_REUSEADDR, (const char*)&opt, sizeof(opt));

    /* Non-blocking so AcceptClient() doesn't stall MQL5 */
    u_long mode = 1;
    ioctlsocket(g_server, FIONBIO, &mode);

    struct sockaddr_in addr;
    ZeroMemory(&addr, sizeof(addr));
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port        = htons((u_short)port);

    if(bind(g_server, (struct sockaddr*)&addr, sizeof(addr)) == SOCKET_ERROR)
    {
        closesocket(g_server);
        g_server = INVALID_SOCKET;
        WSACleanup();
        return -3;
    }

    if(listen(g_server, MAX_CLIENTS) == SOCKET_ERROR)
    {
        closesocket(g_server);
        g_server = INVALID_SOCKET;
        WSACleanup();
        return -4;
    }

    g_initialized = 1;
    return 0;
}

/* ------------------------------------------------------------------ */
/* ServerAccept()                                                      */
/* Returns: client_index (0..MAX_CLIENTS-1) on success               */
/*          -1=not initialized, -2=no pending connection (WOULDBLOCK) */
/*          -3=max clients, -4=accept error, -5=no free slot          */
/* ------------------------------------------------------------------ */
__declspec(dllexport) int __stdcall ServerAccept(void)
{
    if(g_server == INVALID_SOCKET) return -1;

    SOCKET client = accept(g_server, NULL, NULL);
    if(client == INVALID_SOCKET)
    {
        return (WSAGetLastError() == WSAEWOULDBLOCK) ? -2 : -4;
    }

    if(g_client_count >= MAX_CLIENTS)
    {
        closesocket(client);
        return -3;
    }

    /* Non-blocking */
    u_long mode = 1;
    ioctlsocket(client, FIONBIO, &mode);

    /* Find a free slot */
    for(int i = 0; i < MAX_CLIENTS; i++)
    {
        if(g_clients[i] == INVALID_SOCKET)
        {
            g_clients[i] = client;
            g_client_count++;
            return i;
        }
    }

    closesocket(client);
    return -5;
}

/* ------------------------------------------------------------------ */
/* ServerSend(client_idx, data, len)                                  */
/* Returns: bytes sent, or -1=bad index, -2=not connected, -3=error   */
/* ------------------------------------------------------------------ */
__declspec(dllexport) int __stdcall ServerSend(int client_idx, const char *data, int len)
{
    if(client_idx < 0 || client_idx >= MAX_CLIENTS) return -1;
    if(g_clients[client_idx] == INVALID_SOCKET)     return -2;

    int sent = send(g_clients[client_idx], data, len, 0);
    if(sent == SOCKET_ERROR)
    {
        int err = WSAGetLastError();
        if(err == WSAECONNRESET || err == WSAECONNABORTED || err == WSAENOTCONN)
        {
            closesocket(g_clients[client_idx]);
            g_clients[client_idx] = INVALID_SOCKET;
            g_client_count--;
            return -3;
        }
        return -3;
    }
    return sent;
}

/* ------------------------------------------------------------------ */
/* ServerRead(client_idx, buf, len)                                   */
/* Returns: bytes read, 0=no data yet, -1=bad index, -2=not connected */
/*          -3=disconnected                                            */
/* ------------------------------------------------------------------ */
__declspec(dllexport) int __stdcall ServerRead(int client_idx, char *buf, int len)
{
    if(client_idx < 0 || client_idx >= MAX_CLIENTS) return -1;
    if(g_clients[client_idx] == INVALID_SOCKET)     return -2;

    int received = recv(g_clients[client_idx], buf, len, 0);
    if(received == SOCKET_ERROR)
    {
        if(WSAGetLastError() == WSAEWOULDBLOCK) return 0;
        closesocket(g_clients[client_idx]);
        g_clients[client_idx] = INVALID_SOCKET;
        g_client_count--;
        return -3;
    }
    if(received == 0) /* Graceful shutdown */
    {
        closesocket(g_clients[client_idx]);
        g_clients[client_idx] = INVALID_SOCKET;
        g_client_count--;
        return -3;
    }
    return received;
}

/* ------------------------------------------------------------------ */
/* ServerIsReadable(client_idx)                                       */
/* Returns: bytes available, 0=no data, -1=bad index, -2=not connected*/
/* ------------------------------------------------------------------ */
__declspec(dllexport) int __stdcall ServerIsReadable(int client_idx)
{
    if(client_idx < 0 || client_idx >= MAX_CLIENTS) return -1;
    if(g_clients[client_idx] == INVALID_SOCKET)     return -2;

    u_long bytes = 0;
    if(ioctlsocket(g_clients[client_idx], FIONREAD, &bytes) == SOCKET_ERROR)
        return -2;
    return (int)bytes;
}

/* ------------------------------------------------------------------ */
/* ServerIsConnected(client_idx)                                      */
/* Returns: 1=connected, 0=not connected / bad index                  */
/* ------------------------------------------------------------------ */
__declspec(dllexport) int __stdcall ServerIsConnected(int client_idx)
{
    if(client_idx < 0 || client_idx >= MAX_CLIENTS) return 0;
    return (g_clients[client_idx] != INVALID_SOCKET) ? 1 : 0;
}

/* ------------------------------------------------------------------ */
/* ServerCloseClient(client_idx)                                      */
/* Returns: 0=ok, -1=bad index                                        */
/* ------------------------------------------------------------------ */
__declspec(dllexport) int __stdcall ServerCloseClient(int client_idx)
{
    if(client_idx < 0 || client_idx >= MAX_CLIENTS) return -1;
    if(g_clients[client_idx] != INVALID_SOCKET)
    {
        closesocket(g_clients[client_idx]);
        g_clients[client_idx] = INVALID_SOCKET;
        g_client_count--;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* ServerClose() — shutdown server and all clients                    */
/* ------------------------------------------------------------------ */
__declspec(dllexport) void __stdcall ServerClose(void)
{
    for(int i = 0; i < MAX_CLIENTS; i++)
    {
        if(g_clients[i] != INVALID_SOCKET)
        {
            closesocket(g_clients[i]);
            g_clients[i] = INVALID_SOCKET;
        }
    }
    g_client_count = 0;

    if(g_server != INVALID_SOCKET)
    {
        closesocket(g_server);
        g_server = INVALID_SOCKET;
    }

    WSACleanup();
    g_initialized = 0;
}
