/*
    Weave (Web-based Analysis and Visualization Environment)
    Copyright (C) 2008-2011 University of Massachusetts Lowell

    This file is a part of Weave.

    Weave is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License, Version 3,
    as published by the Free Software Foundation.

    Weave is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Weave.  If not, see <http://www.gnu.org/licenses/>.
*/

package weave.visualization.plotters
{
	import flash.display.BitmapData;
	import flash.display.Graphics;
	import flash.geom.Point;
	
	import mx.rpc.AsyncToken;
	import mx.rpc.events.FaultEvent;
	import mx.rpc.events.ResultEvent;
	
	import weave.Weave;
	import weave.api.disposeObjects;
	import weave.api.core.IDisposableObject;
	import weave.api.getCallbackCollection;
	import weave.api.newLinkableChild;
	import weave.api.primitives.IBounds2D;
	import weave.api.registerLinkableChild;
	import weave.api.reportError;
	import weave.core.LinkableBoolean;
	import weave.core.LinkableString;
	import weave.core.LinkableNumber;
	import weave.data.AttributeColumns.DynamicColumn;
	import weave.primitives.Range;
	import weave.services.WeaveRServlet;
	import weave.services.addAsyncResponder;
	import weave.services.beans.RResult;
	import weave.utils.ColumnUtils;
	import weave.visualization.plotters.styles.SolidLineStyle;
	
	/**
	 * RegressionLinePlotter
	 * 
	 * @author kmanohar
	 */
	public class RegressionLinePlotter extends AbstractPlotter implements IDisposableObject
	{
		public function RegressionLinePlotter()
		{
			Weave.properties.rServiceURL.addImmediateCallback(this, resetRService, true);
			spatialCallbacks.addImmediateCallback(this, resetRegressionLine );
			spatialCallbacks.addGroupedCallback(this, calculateRRegression );
			setColumnKeySources([xColumn, yColumn]);
			
			// hack to fix old session states
			_filteredKeySet.addImmediateCallback(this, function():void {
				if (_filteredKeySet.keyFilter.internalObject == null)
					_filteredKeySet.keyFilter.globalName = Weave.DEFAULT_SUBSET_KEYFILTER;
			});
		}
		
		public const drawLine:LinkableBoolean = registerSpatialProperty(new LinkableBoolean(false));
		
		public const xColumn:DynamicColumn = newSpatialProperty(DynamicColumn);
		public const yColumn:DynamicColumn = newSpatialProperty(DynamicColumn);
		
		public const lineStyle:SolidLineStyle = newLinkableChild(this, SolidLineStyle);

		private var rService:WeaveRServlet = null;
		
		private function resetRService():void
		{
			rService = new WeaveRServlet(Weave.properties.rServiceURL.value);
		}
		
		private function resetRegressionLine():void
		{
			// clear previous values
			slope = NaN;
			intercept = NaN;
		}
		private function calculateRRegression():void
		{
				var Rstring:String = null;
				var dataXY:Array = null;
				var token:AsyncToken = null;
				
			if (currentTrendline.value == LINEAR) {
				//trace( "calculateRegression() " + xColumn.toString() );
				Rstring = "fit <- lm(y~x)\n"
					+"intercept <- coefficients(fit)[1]\n"
					+"slope <- coefficients(fit)[2]\n"
					+"rSquared <- summary(fit)$r.squared\n";			
				dataXY = ColumnUtils.joinColumns([xColumn, yColumn], Number, false, filteredKeySet.keys);
				
			
				// sends a request to Rserve to calculate the slope and intercept of a regression line fitted to xColumn and yColumn 
				token = rService.runScript(null,["x","y"],[dataXY[1],dataXY[2]],["intercept","slope","rSquared"],Rstring,"",false,false,false);
				addAsyncResponder(token, handleLinearRegressionResult, handleLinearRegressionFault, ++requestID);
			}
			
			if (currentTrendline.value == POLYNOMIAL) {
				//trace( "calculateRegression() " + xColumn.toString() );
				Rstring = "fit <- lm(y ~ poly(x, 2, raw = TRUE))\n"
					+"c <- coefficients(fit)[1]\n"
					+"b <- coefficients(fit)[2]\n"
					+"a <- coefficients(fit)[3]\n"
					+"rSquared <- summary(fit)$r.squared\n";			
				dataXY = ColumnUtils.joinColumns([xColumn, yColumn], Number, false, filteredKeySet.keys);
				
				
				// sends a request to Rserve to calculate the coefficients of the regression polynomial fitted to xColumn and yColumn 
				token = rService.runScript(null,["x","y"],[dataXY[1],dataXY[2]],["c","b","a", "rSquared"],Rstring,"",false,false,false);
				addAsyncResponder(token, handleLinearRegressionResult, handleLinearRegressionFault, ++requestID);
			}
			
			if (currentTrendline.value == LOGARITHMIC) {
				
			}
			
			if (currentTrendline.value == EXPONENTIAL) {
				
			}
			
			if (currentTrendline.value == POWER) {
				
			}
			
			
		}
		private var requestID:int = 0; // ID of the latest request, used to ignore old results
		
		private function handleLinearRegressionResult(event:ResultEvent, token:Object=null):void
		{
			if (this.requestID != int(token))
			{
				// ignore outdated results
				return;
			}
			
			var Robj:Array = event.result as Array;
			if (Robj == null)
				return;
			
			var RresultArray:Array = new Array();
			
			//collecting Objects of type RResult(Should Match result object from Java side)
			for(var i:int = 0; i<Robj.length; i++)
			{
				var rResult:RResult = new RResult(Robj[i]);
				RresultArray.push(rResult);				
			}
			
			if (RresultArray.length > 1)
			{
				if (currentTrendline.value == LINEAR) {
					intercept = (Number((RresultArray[0] as RResult).value) != intercept) ? Number((RresultArray[0] as RResult).value) : NaN ;
					slope = Number((RresultArray[1] as RResult).value);
					rSquared = Number((RresultArray[2] as RResult).value);	
					//trace( "R" + " " + intercept + " " + slope) ;
					getCallbackCollection(this).triggerCallbacks();
				}
				
				if (currentTrendline.value == POLYNOMIAL) {
					
					if (polynomialDegree.value == 2) {
						c = (Number((RresultArray[0] as RResult).value) != intercept) ? Number((RresultArray[0] as RResult).value) : NaN ;
						b = Number((RresultArray[1] as RResult).value);
						a = Number((RresultArray[2] as RResult).value);
						rSquared = Number((RresultArray[3] as RResult).value);	
						//trace( "R" + " " + intercept + " " + slope) ;
						getCallbackCollection(this).triggerCallbacks();	
						
					}
					
					if (polynomialDegree.value == 3) {
						
						
					}
					
					if (polynomialDegree.value == 4) {
						
						
					}
					
					if (polynomialDegree.value == 5) {
						
						
					}
					
					if (polynomialDegree.value == 5) {
						
						
					}
					
				}
				
				if (currentTrendline.value == EXPONENTIAL) {
					
				}
				
				if (currentTrendline.value == POWER) {
					
				}
				
				if (currentTrendline.value == LOGARITHMIC) {
					
					
				}
			}
			
		}
		
		private function handleLinearRegressionFault(event:FaultEvent, token:Object = null):void
		{
			if (this.requestID != int(token))
			{
				// ignore outdated results
				return;
			}
			
			reportError(event);
			intercept = NaN;
			slope = NaN;
			getCallbackCollection(this).triggerCallbacks();
		}
		
		public function getSlope():Number { return slope; }
		public function getIntercept():Number { return intercept; }

		private var intercept:Number = NaN;
		private var slope:Number = NaN;
		private var rSquared:Number = NaN;
		private var a:Number = NaN;
		private var b:Number = NaN;
		private var c:Number = NaN;
		private var d:Number = NaN;
		private var e:Number = NaN;
		private var f:Number = NaN;
		private var g:Number = NaN;
		private var tempRange:Range = new Range();
		private var tempPoint:Point = new Point();
		private var tempPoint2:Point = new Point();

		override public function drawBackground(dataBounds:IBounds2D, screenBounds:IBounds2D, destination:BitmapData):void
		{
			if(currentTrendline.value)
			{
				var g:Graphics = tempShape.graphics; 
				g.clear();
				
				if(!isNaN(intercept))
				{
					tempPoint.x = dataBounds.getXMin();
					tempPoint2.x = dataBounds.getXMax();
					
					tempPoint.y = (slope*tempPoint.x)+intercept;
					tempPoint2.y = (slope*tempPoint2.x)+intercept;
					
					tempRange.setRange( dataBounds.getYMin(), dataBounds.getYMax() );
					
					// constrain yMin to be within y range and derive xMin from constrained yMin
					tempPoint.x = tempPoint.x + (tempRange.constrain(tempPoint.y) - tempPoint.y) / slope;
					tempPoint.y = tempRange.constrain(tempPoint.y);
					
					// constrain yMax to be within y range and derive xMax from constrained yMax
					tempPoint2.x = tempPoint.x + (tempRange.constrain(tempPoint2.y) - tempPoint.y) / slope;
					tempPoint2.y = tempRange.constrain(tempPoint2.y);
					
					dataBounds.projectPointTo(tempPoint,screenBounds);
					dataBounds.projectPointTo(tempPoint2,screenBounds);
					lineStyle.beginLineStyle(null,g);
					//g.lineStyle(lineThickness.value, lineColor.value,lineAlpha.value,true,LineScaleMode.NONE);
					g.moveTo(tempPoint.x,tempPoint.y);
					g.lineTo(tempPoint2.x,tempPoint2.y);
					
					destination.draw(tempShape);
				}
			}		
		}
		public function dispose():void
		{
			requestID = 0; // forces all results from previous requests to be ignored
		}
		

		// Trendlines
		public const polynomialDegree:LinkableNumber = registerLinkableChild(this, new LinkableNumber(2), calculateRRegression);
		public const currentTrendline:LinkableString = registerLinkableChild(this, new LinkableString(LINEAR), calculateRRegression);

		[Bindable] public var trendlines:Array = [LINEAR, POLYNOMIAL, LOGARITHMIC, EXPONENTIAL, POWER];
		public static const LINEAR:String = "Linear";
		public static const POLYNOMIAL:String = "Polynomial";
		public static const LOGARITHMIC:String = "Logarithmic";
		public static const EXPONENTIAL:String = "Exponential";
		public static const POWER:String = "Power";
	}
}
