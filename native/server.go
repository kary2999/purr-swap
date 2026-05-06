// USDT 换汇 Mac app 的本地 server (静态二进制).
// 1) 托管 Flutter web 构建产物 (static dir from arg)
// 2) /proxy/?url=<urlencoded> 反代外部 API,避开 CORS
//
// 编译:
//   GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o server-arm64 server.go
//   GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -o server-amd64 server.go
//   lipo -create server-arm64 server-amd64 -output server
package main

import (
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

const ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
	"(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

var client = &http.Client{Timeout: 10 * time.Second}

func setCORS(w http.ResponseWriter) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "*")
}

func proxy(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodOptions {
		setCORS(w)
		w.WriteHeader(http.StatusNoContent)
		return
	}
	raw := r.URL.Query().Get("url")
	if raw == "" {
		http.Error(w, "missing url", http.StatusBadRequest)
		return
	}
	target, err := url.QueryUnescape(raw)
	if err != nil {
		target = raw
	}

	body := r.Body
	defer body.Close()

	req, err := http.NewRequest(r.Method, target, body)
	if err != nil {
		setCORS(w)
		http.Error(w, "bad target: "+err.Error(), http.StatusBadRequest)
		return
	}
	for _, h := range []string{"Content-Type", "Accept", "Accept-Language", "Referer"} {
		if v := r.Header.Get(h); v != "" {
			req.Header.Set(h, v)
		}
	}
	req.Header.Set("User-Agent", ua)

	resp, err := client.Do(req)
	if err != nil {
		setCORS(w)
		http.Error(w, "proxy err: "+err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	setCORS(w)
	if ct := resp.Header.Get("Content-Type"); ct != "" {
		w.Header().Set("Content-Type", ct)
	}
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func wrap(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		setCORS(w)
		h.ServeHTTP(w, r)
	})
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: server <web-dir>")
		os.Exit(1)
	}
	webDir := os.Args[1]
	// Port 0: OS 自动分配空闲端口
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Fatal(err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	fmt.Println(port) // launcher 通过 stdout 首行拿端口

	mux := http.NewServeMux()
	mux.HandleFunc("/proxy/", proxy)

	fs := http.FileServer(http.Dir(webDir))
	mux.Handle("/", wrap(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// 避免缓存
		if strings.HasSuffix(r.URL.Path, ".html") || r.URL.Path == "/" {
			w.Header().Set("Cache-Control", "no-store")
		}
		fs.ServeHTTP(w, r)
	})))

	srv := &http.Server{Handler: mux}
	log.Println("serving on", ln.Addr())
	log.Fatal(srv.Serve(ln))
}
