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

	http.ListenAndServe(":3450", nil)
	
	fmt.Println("Stopped Tmunot 1.0")
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "This is a test")
}
