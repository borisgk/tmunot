package main

import (
	"fmt"
	"log"
	"net/http"
)

func main() {
	fmt.Println("Started Tmunot 1.0")

	log.Println("Log entry: everything OK.")

	http.HandleFunc("/", homeHandler)

	err := http.ListenAndServe(":3450", nil)

	if err != nil {
		log.Fatal(err)
	}

	fmt.Println("Stopped Tmunot 1.0")
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "<html><head></head><body><center><h1>This is a test</h1></center></body></html>")
}
