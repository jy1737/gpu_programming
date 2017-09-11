// ###
// ###
// ### Practical Course: GPU Programming in Computer Vision
// ###
// ###
// ### Technical University Munich, Computer Vision Group
// ### Summer Semester 2017, September 11 - October 9
// ###

// Written by: Jiho Yang (M.Sc student in Computational Science & Engineering)
// Matriculation number: 03675799

#include "helper.h"
#include <iostream>
using namespace std;

// uncomment to use the camera
//#define CAMERA

// Gamma correction
__global__ void gamma_correction(float *d_imgOut, float *d_imgIn, int sizeImg, float gamma){
	for (int i = 0; i < sizeImg; i++){
		d_imgOut[i] = (d_imgIn[i])^gamma;
	}
}

// Compute gradient
__global__ void compute_gradient(float *d_gradx, float *d_grady, float *d_imgIn, int w, int h, int nc){
	size_t countx = 0;
	size_t county = 0;
	for (int c = 0; c < nc; c++){
		for (int y = 0; y < h - 1; y++){
			for (int x = 0; x < w - 1; x++){
				size_t x_high = x + 1 + (size_t)w*y + (size_t)w*h*c;
				size_t y_high = x + (size_t)w*(y+1) + (size_t)w*h*c;
				size_t low = x + (size_t)w*y + (size_t)w*h*c;
				// Gradient in x
				d_gradx[countx] = d_imgIn[x_high] - d_imgIn[low];
				countx += 1;
				// Gradient in y
				d_grady[county] = d_imgIn[y_high] - d_imgIn[low];
				county += 1;
			}
			x = (size_t)w - 1;
			// Update y_high and low
			size_t y_high = x + (size_t)w*(y+1) + (size_t)w*h*c;
			size_t low = x + (size_t)w*y + (size_t)w*h*c;
			// x boundary
			d_gradx[countx] = 0;
			countx += 1;
			// Gradient in y
			d_grady[county] = d_imgIn[y_high] - d_imgIn[low];
			county += 1;
		}
		y = (size_t)h - 1;
		for (int x = 0; x < w - 1; x++){
			// Update x_high and low
			size_t x_high = x + 1 + (size_t)w*y + (size_t)w*h*c;
			size_t low = x + (size_t)w*y + (size_t)w*h*c;
			// Gradient in x
			d_gradx[countx] = d_imgIn[x_high] - d_imgIn[low];
			countx += 1;
			// y boundary
			d_grady[county] = 0;
			county += 1;
		}
		x = (size_t)w - 1;
		// x boundary
		d_gradx[countx] = 0;
		countx += 1;
		// y boundary
		d_grady[county] = 0;
		county += 1;
	}
}

__global__ void compute_divergence(float *d_div, float *d_imgIn, int w, int h, int nc){
	size_t count = 0;
	for (int c = 0; c < nc; c++){
		y = 0;
		x = 0;
		// x and y boundary
		d_div[count] = 0;
		count += 1;
		for (int x = 1; x < w; x++){
			// Update x_low
			size_t x_low = x - 1 + (size_t)w*y + (size_t)w*h*c;
			// Divergence
			d_div[count] = d_imgIn[high] - d_imgIn[x_low];
			count += 1;
		}
		for (int y = 1; y < h; y++){
			x = 0;
			// Update y_low
			size_t y_low = x + (size_t)w*(y-1) + (size_t)w*h*c;
			size_t high  = x + (size_t)w*y + (size_t)w*h*c;
			// Divergence
			d_div[count] = d_imgIn[high] - d_imgIn[y_low];
			count += 1;
			for (int x = 1; x < w; x++){
				// Update x_low and y_low
				size_t x_low = x - 1 + (size_t)w*y + (size_t)w*h*c;
				size_t y_low = x + (size_t)w*(y-1) + (size_t)w*h*c;
				size_t high = x + (size_t)w*y + (size_t)w*h*c;
				// Divergence
				d_div[count] = 2*d_imgIn[high] - d_imgIn[x_low] - d_imgIn[y_low];
				count += 1;
			}
		}
	}
}

//__global__ void compute_norm



int main(int argc, char **argv)
{
    // Before the GPU can process your kernels, a so called "CUDA context" must be initialized
    // This happens on the very first call to a CUDA function, and takes some time (around half a second)
    // We will do it right here, so that the run time measurements are accurate
    cudaDeviceSynchronize();  CUDA_CHECK;




    // Reading command line parameters:
    // getParam("param", var, argc, argv) looks whether "-param xyz" is specified, and if so stores the value "xyz" in "var"
    // If "-param" is not specified, the value of "var" remains unchanged
    //
    // return value: getParam("param", ...) returns true if "-param" is specified, and false otherwise

#ifdef CAMERA
#else
    // input image
    string image = "";
    bool ret = getParam("i", image, argc, argv);
    if (!ret) cerr << "ERROR: no image specified" << endl;
    if (argc <= 1) { cout << "Usage: " << argv[0] << " -i <image> [-repeats <repeats>] [-gray]" << endl; return 1; }
#endif
    
    // number of computation repetitions to get a better run time measurement
    int repeats = 1;
    getParam("repeats", repeats, argc, argv);
    cout << "repeats: " << repeats << endl;
    
    // load the input image as grayscale if "-gray" is specifed
    bool gray = false;
    getParam("gray", gray, argc, argv);
    cout << "gray: " << gray << endl;

    // ### Define your own parameters here as needed    

    // Init camera / Load input image
#ifdef CAMERA

    // Init camera
  	cv::VideoCapture camera(0);
  	if(!camera.isOpened()) { cerr << "ERROR: Could not open camera" << endl; return 1; }
    int camW = 640;
    int camH = 480;
  	camera.set(CV_CAP_PROP_FRAME_WIDTH,camW);
  	camera.set(CV_CAP_PROP_FRAME_HEIGHT,camH);
    // read in first frame to get the dimensions
    cv::Mat mIn;
    camera >> mIn;
    
#else
    
    // Load the input image using opencv (load as grayscale if "gray==true", otherwise as is (may be color or grayscale))
    cv::Mat mIn = cv::imread(image.c_str(), (gray? CV_LOAD_IMAGE_GRAYSCALE : -1));
    // check
    if (mIn.data == NULL) { cerr << "ERROR: Could not load image " << image << endl; return 1; }
    
#endif

    // convert to float representation (opencv loads image values as single bytes by default)
    mIn.convertTo(mIn,CV_32F);
    // convert range of each channel to [0,1] (opencv default is [0,255])
    mIn /= 255.f;
    // get image dimensions
    int w = mIn.cols;         // width
    int h = mIn.rows;         // height
    int nc = mIn.channels();  // number of channels
    cout << "image: " << w << " x " << h << endl;




    // Set the output image format
    // ###
    // ###
    // ### TODO: Change the output image format as needed
    // ###
    // ###
    cv::Mat mOut(h,w,mIn.type());  // mOut will have the same number of channels as the input image, nc layers
    //cv::Mat mOut(h,w,CV_32FC3);    // mOut will be a color image, 3 layers
    //cv::Mat mOut(h,w,CV_32FC1);    // mOut will be a grayscale image, 1 layer
    // ### Define your own output images here as needed




    // Allocate arrays
    // input/output image width: w
    // input/output image height: h
    // input image number of channels: nc
    // output image number of channels: mOut.channels(), as defined above (nc, 3, or 1)

    // allocate raw input image array
    float *imgIn = new float[(size_t)w*h*nc];

    // allocate raw output array (the computation result will be stored in this array, then later converted to mOut for displaying)
    float *imgOut = new float[(size_t)w*h*mOut.channels()];




    // For camera mode: Make a loop to read in camera frames
#ifdef CAMERA
    // Read a camera image frame every 30 milliseconds:
    // cv::waitKey(30) waits 30 milliseconds for a keyboard input,
    // returns a value <0 if no key is pressed during this time, returns immediately with a value >=0 if a key is pressed
    while (cv::waitKey(30) < 0)
    {
    // Get camera image
    camera >> mIn;
    // convert to float representation (opencv loads image values as single bytes by default)
    mIn.convertTo(mIn,CV_32F);
    // convert range of each channel to [0,1] (opencv default is [0,255])
    mIn /= 255.f;
#endif

    // Init raw input image array
    // opencv images are interleaved: rgb rgb rgb...  (actually bgr bgr bgr...)
    // But for CUDA it's better to work with layered images: rrr... ggg... bbb...
    // So we will convert as necessary, using interleaved "cv::Mat" for loading/saving/displaying, and layered "float*" for CUDA computations
    convert_mat_to_layered (imgIn, mIn);


    Timer timer; timer.start();
    // ###
    // ###
    // ### TODO: Main computation
    // ###
    // ###
    timer.end();  float t = timer.get();  // elapsed time in seconds
    cout << "time: " << t*1000 << " ms" << endl;

	int sizeImg = (int)w*h*nc;
	size_t nbytes = (size_t)(sizeImg)*sizeof(float);
	float gamma = 5.0f;

	///////////////////////////////// Gamma correction - CPU Computation /////////////////////////////////

	/*for (int i = 0; i < sizeImg; i++){
		imgOut[i] = pow(imgIn[i], gamma);
	}*/

	//////////////////////////////////////////////////////////////////////////////////////////////////////


	///////////////////////////////// Gamma correction - GPU Computation /////////////////////////////////

	float *d_imgOut = NULL;	
	float *d_imgIn  = NULL; 
	cudaMalloc(&d_imgIn, nbytes);	CUDA_CHECK;
	cudaMalloc(&d_imgOut, nbytes);	CUDA_CHECK;
	cudaMemcpy(d_imgIn, imgIn, nbytes, cudaMemcpyHostToDevice);	CUDA_CHECK;
	// Launch kernel
    dim3 block = dim3(128, 1, 1);
    dim3 grid = dim3((sizeImg+block.x-1)/block.x, 1, 1);
	// Execute gamma correction
	gamma_correction <<<grid, block>>> (d_imgOut, d_imgIn, sizeImg, gamma);
	// Copy back to CPU
	cudaMemcpy(imgOut, d_imgOut, nbytes, cudaMemcpyDeviceToHost); CUDA_CHECK;

	////////////////////////////////////////////// Gradient //////////////////////////////////////////////

	float *d_gradx = NULL;
	float *d_grady = NULL;
	cudaMalloc(&d_gradx, nbytes); CUDA_CHECK;
	cudaMalloc(&d_grady, nbytes); CUDA_CHECK;
	// Launch kernel
	dim3 block = dim3(128, 1, 1);
	dim3 grid = dim3((sizeImg+block.x-1)/block.x, 1, 1);
	// Compute gradient
	compute_gradient <<<grid, block>>> (d_gradx, d_grady, d_imgIn, w, h, nc);
	// Copy back to CPU
	cudaMemcpy(imgOut, d_gradx, nbytes, cudaMemcpyDeviceToHost); CUDA_CHECK;
	//cudaMemcpy(imgOut, d_grady, nbytes, cudaMemcpyDeviceToHost); CUDA_CHECK;

	//////////////////////////////////////////// Divergence /////////////////////////////////////////////
	float *d_div = NULL;
	cudaMalloc(&d_div, nbytes); CUDA_CHECK;
	cudaMemcpy(d_imgIn, imgIn, nbytes, cudaMemcpyHostToDevice); CUDA_CHECK;
	// Launch kernel
	dim3 block = dim3(128, 1, 1);
	dim3 grid = dim3((sizeImg+block.x-1)/block.x, 1, 1);
	// Compute divergence
	compute_divergence <<<grid, block>>> (d_div, d_imgIn, w, h, nc);
	// Copy back to CPU
	cudaMemcpy(imgOut, d_div, nbytes, cudaMemcpyDeviceToHost); CUDA_CHECK;

	/////////////////////////////////////////////////////

	// Free memory
	cudaFree(d_imgIn); CUDA_CHECK;
	cudaFree(d_imgOut); CUDA_CHECK;
	cudaFree(d_gradx); CUDA_CHECK;
	cudaFree(d_grady); CUDA_CHECK;
	cudaFree(d_div);	CUDA_CHECK;

	/////////////////////////////////////////////////////

    // show input image
    showImage("Input", mIn, 100, 100);  // show at position (x_from_left=100,y_from_above=100)

    // show output image: first convert to interleaved opencv format from the layered raw array
    convert_layered_to_mat(mOut, imgOut);
    showImage("Output", mOut, 100+w+40, 100);

    // ### Display your own output images here as needed

#ifdef CAMERA
    // end of camera loop
    }
#else
    // wait for key inputs
    cv::waitKey(0);
#endif




    // save input and result
    cv::imwrite("image_input.png",mIn*255.f);  // "imwrite" assumes channel range [0,255]
    cv::imwrite("image_result.png",mOut*255.f);

    // free allocated arrays
    delete[] imgIn;
    delete[] imgOut;

    // close all opencv windows
    cvDestroyAllWindows();
    return 0;
}



