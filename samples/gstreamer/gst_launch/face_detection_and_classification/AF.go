package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"time"
)

type Model struct {
	Name string `json:"name"`
}

type Age struct {
	Label uint  `json:"label"`
	Model Model `json:"model"`
}

type BoundingBox struct {
	XMax float64 `json:"x_max"`
	XMin float64 `json:"x_min"`
	YMax float64 `json:"y_max"`
	YMin float64 `json:"y_min"`
}

type Detection struct {
	BoundingBox BoundingBox `json:"bounding_box"`
	Confidence  float64     `json:"confidence"`
	LabelID     int         `json:"label_id"`
}

type Emotion struct {
	Confidence float64 `json:"confidence"`
	Label      string  `json:"label"`
	LabelID    int     `json:"label_id"`
	Model      Model   `json:"model"`
}

type Gender struct {
	Confidence float64 `json:"confidence"`
	Label      string  `json:"label"`
	LabelID    int     `json:"label_id"`
	Model      Model   `json:"model"`
}

type Object struct {
	Age       Age       `json:"age"`
	Detection Detection `json:"detection"`
	Emotion   Emotion   `json:"emotion"`
	Gender    Gender    `json:"gender"`
	H         int       `json:"h"`
	RegionID  int       `json:"region_id"`
	W         int       `json:"w"`
	X         int       `json:"x"`
	Y         int       `json:"y"`
}

type Resolution struct {
	Height int `json:"height"`
	Width  int `json:"width"`
}

type GvaMeta struct {
	Objects    []Object   `json:"objects"`
	Resolution Resolution `json:"resolution"`
	TimeStamp  uint64     `json:"timestamp"`
}

func reader(fifoFile string, ch chan []byte) {

	// Open pipe for read only
	fmt.Println("Starting read operation")
	pipe, err := os.OpenFile(fifoFile, os.O_RDONLY, 0640)
	if err != nil {
		fmt.Println("Couldn't open pipe with error: ", err)
	}
	defer pipe.Close()

	// Read the content of named pipe
	reader := bufio.NewReader(pipe)
	fmt.Println("READER >> created")

	// Infinite loop
	for {
		line, err := reader.ReadBytes('\n')
		// Close the pipe once EOF is reached
		if err != nil {
			fmt.Println("FINISHED!")
			os.Exit(0)
		}

		ch <- line
	}
}

func consumer(ch chan []byte, inactiveTimer uint, nefSvcEndpoint string, nefJson string) {
	state := 0
	timer := time.NewTimer(time.Duration(inactiveTimer) * time.Second)
	for {
		select {
		case line := <-ch:
			meta := GvaMeta{}
			json.Unmarshal(line, &meta)
			fmt.Printf("%+v\n", meta)
			if state == 0 {
				fmt.Printf("Object detected=>Fire NEF Post\n")
				state = 1
			}
			timer = time.NewTimer(5 * time.Second)
		case <-timer.C:
			if state == 1 {
				state = 0
				fmt.Printf("No object detected for %d secs=>Fire NEF Del\n", inactiveTimer)
			}
		}
	}
}

func main() {
	fifoFile := flag.String("fifoFile", "output.json", "fifo filename")
	inactiveTimer := flag.Uint("inactiveTimer", 10, "Inactive length before firing NEF delete")
	nefSvcEndpoint := flag.String("nefSvcEndpoint", "", "NEF service endpoint")
	nefJson := flag.String("nefJson", "", "NEF post json for QoS provisioning")

	flag.Parse()

	fmt.Printf("STARTED %s\n", *fifoFile)
	ch := make(chan []byte)
	go consumer(ch, *inactiveTimer, *nefSvcEndpoint, *nefJson)
	reader(*fifoFile, ch)
}
